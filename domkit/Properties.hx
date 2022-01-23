package domkit;

enum SetAttributeResult {
	Ok;
	Unknown;
	Unsupported;
	InvalidValue( ?msg : String );
}

private class DirtyRef {
	var dirty : Bool;
	public function new() {
		mark();
	}
	public inline function mark() {
		dirty = true;
	}
}

class Properties<T:Model<T>> {

	public var id(default,null) : String;
	public var obj(default,null) : Model<T>;
	public var component(default,null) : Component<T,Dynamic>;
	public var hover(default,set) : Bool = false;
	public var active(default,set) : Bool = false;
	public var disabled(default,set) : Bool = false;
	public var parent(get,never) : Properties<T>;
	public var contentRoot(default,null) : Model<T>;

	var classes : Array<String>;
	var style : Array<{ p : Property, value : Any }> = [];
	var currentSet : Array<Property> = [];
	var currentValues : Array<CssValue>; // only for inspector
	var transitionValues : Map<Int,Dynamic>;
	var needStyleRefresh : Bool = true;
	var firstInit : Bool = true;
	var transitionCount : Int = 0;
	var dirty : DirtyRef;

	static var KEEP_VALUES = false;

	public function new(obj,component) {
		this.obj = obj;
		this.component = component;
		this.contentRoot = obj;
		onParentChanged();
		dirty.mark();
	}

	inline function needRefresh() {
		needStyleRefresh = true;
		dirty.mark();
	}

	public function getClasses() : Iterable<String> {
		return classes == null ? [] : classes;
	}

	public function hasClass( name : String ) {
		if( classes == null )
			return false;
		return classes.indexOf(name) >= 0;
	}

	public function onParentChanged() {
		var p = parent;
		if( p == null )
			dirty = new DirtyRef();
		else {
			dirty = p.dirty;
			needRefresh();
		}
		for( c in obj.getChildren() )
			if( c.dom != null )
				c.dom.onParentChanged();
	}

	inline function get_parent() : Properties<T> {
		var p = obj.parent;
		return p == null ? null : cast p.dom;
	}

	public function addClass( c : String ) {
		if( classes == null )
			classes = [];
		if( classes.indexOf(c) < 0 ) {
			classes.push(c);
			needRefresh();
		}
	}

	public function applyStyle( style : CssStyle, partialRefresh = false ) @:privateAccess {
		if( partialRefresh && !dirty.dirty ) return;
		style.applyStyle(this, !partialRefresh);
		// if we did apply the style to a children element manually, we should not mark things
		// as done as some parents styles might have not yet been updated
		if( parent == null ) dirty.dirty = false;
	}

	public function removeClass( c : String ) {
		if( classes == null )
			return;
		if( classes.remove(c) ) {
			needRefresh();
			if( classes.length == 0 ) classes = null;
		}
	}

	public function toggleClass( c : String, ?b : Bool ) {
		if( b == null ) {
			if( classes == null )
				classes = [c];
			else if( classes.remove(c) ) {
				if( classes.length == 0 ) classes = null;
			} else
				classes.push(c);
			needRefresh();
		} else if( b )
			addClass(c);
		else
			removeClass(c);
	}

	function set_hover(b) {
		if( hover == b ) return b;
		needRefresh();
		return hover = b;
	}

	function set_active(b) {
		if( active == b ) return b;
		needRefresh();
		return active = b;
	}

	function set_disabled(b) {
		if( disabled == b ) return b;
		needRefresh();
		return disabled = b;
	}

	function initStyle( p : String, value : Dynamic ) {
		style.push({ p : Property.get(p), value : value });
		needRefresh();
	}

	public function initAttributes( attr : haxe.DynamicAccess<String> ) {
		var parser = new CssParser();
		for( a in attr.keys() ) {
			var ret;
			var p = Property.get(a,false);
			if( p == null )
				ret = Unknown;
			else {
				var h = component.getHandler(p);
				if( h == null && p != pclass && p != pid )
					ret = Unsupported;
				else
					ret = setAttribute(a, parser.parseValue(attr.get(a)));
			}
			#if sys
			if( ret != Ok ) {
				if( ret.match(InvalidValue(null)) ) ret = InvalidValue(attr.get(a));
				Sys.println(component.name+"."+a+"> "+ret);
			}
			#end
		}
	}

	public function setClasses( cl : String ) {
		var cl = cl.split(" ");
		classes = [];
		for( c in cl ) {
			var c = StringTools.trim(c);
			if( c.length == 0 ) continue;
			classes.push(c);
		}
		needRefresh();
	}

	/**
	 * Will remove other class starting with `kind-` and enable `kind-value` class instead
	 */
	public function setClassKind( kind : String, value : String ) {
		kind += "-";
		var full = kind + value;
		if( classes == null ) classes = [];
		for( c in classes )
			if( StringTools.startsWith(c,kind) ) {
				if( c == full ) return;
				classes.remove(c);
				break;
			}
		classes.push(full);
		needRefresh();
	}

	public function setAttribute( p : String, value : CssValue ) : SetAttributeResult {
		var p = Property.get(p,false);
		if( p == null )
			return Unknown;
		if( p.id == pid.id ) {
			switch( value ) {
			case VIdent(i):
				if( id != i ) {
					id = i;
					updateComponentId(this);
					needRefresh();
				}
			default: return InvalidValue();
			}
			return Ok;
		}
		if( p.id == pclass.id ) {
			// keep previous classes !! (declaring component <xxx class="foo"/> should not erase previous classes)
			if( classes == null )
				classes = [];
			switch( value ) {
			case VIdent(i): classes.push(i);
			case VGroup(vl): for( v in vl ) switch( v ) { case VIdent(i): classes.push(i); default: return InvalidValue(); }
			default: return InvalidValue();
			}
			needRefresh();
			return Ok;
		}
		var handler = component.getHandler(p);
		if( handler == null )
			return Unsupported;
		var v : Dynamic;
		try {
			v = handler.parser(value);
		} catch( e : Property.InvalidProperty ) {
			return InvalidValue(e.message);
		}
		var found = false;
		for( s in style )
			if( s.p == p ) {
				s.value = v;
				style.remove(s);
				style.push(s);
				found = true;
				break;
			}
		if( !found ) {
			style.push({ p : p , value : v });
			for( s in currentSet )
				if( s == p ) {
					found = true;
					if( KEEP_VALUES ) {
						initCurrentValues();
						currentValues[currentSet.indexOf(p)] = value;
					}
					break;
				}
			if( !found ) {
				if( KEEP_VALUES ) {
					initCurrentValues();
					currentValues.push(value);
				}
				currentSet.push(p);
			}
		}
		if( p.hasTransition ) {
			if( transitionValues == null ) transitionValues = new Map();
			transitionValues.set(p.id, v);
		}
		handler.apply(obj,v);
		return Ok;
	}

	function initCurrentValues() {
		if( currentValues == null )
			currentValues = [for( s in currentSet ) null];
	}

	static var pclass = Property.get("class");
	static var pid = Property.get("id");

	static dynamic function updateComponentId( p : Properties<Dynamic> ) {
	}

	public static function create<BaseT:Model<BaseT>,T:BaseT>( comp : String, value : T, ?attributes : haxe.DynamicAccess<String> ) {
		if( value == null ) throw "Component value is not set";
		var c = Component.get(comp);
		var p = new Properties<BaseT>(value, cast c);
		if( attributes != null )
			p.initAttributes(attributes);
		return p;
	}

	static function createNew<T:Model<T>>( comp : String, parent : Properties<T>, args : Array<Dynamic>, ?attributes : haxe.DynamicAccess<String> ) : Properties<T> {
		var c = Component.get(comp);
		var value : T = c.make(args, parent.contentRoot);
		var p : Properties<T> = cast value.dom;
		if( p == null )
			value.dom = cast (p = new Properties<T>(value, cast c));
		if( attributes != null )
			p.initAttributes(attributes);
		return p;
	}

}
