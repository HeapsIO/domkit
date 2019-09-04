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
	public var obj(default,null) : T;
	public var component(default,null) : Component<T,Dynamic>;
	public var hover(default,set) : Bool = false;
	public var active(default,set) : Bool = false;
	public var parent(get,never) : Properties<T>;

	var classes : Array<String>;
	var style : Array<{ p : Property, value : Any }> = [];
	var currentSet : Array<Property> = [];
	var needStyleRefresh : Bool = true;
	var dirty : DirtyRef;

	public function new(obj,component) {
		this.obj = obj;
		this.component = component;
		onParentChanged();
		dirty.mark();
	}

	inline function needRefresh() {
		needStyleRefresh = true;
		dirty.mark();
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

	inline function get_parent() {
		var p = obj.parent;
		return p == null ? null : p.dom;
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
		dirty.dirty = false;
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
			switch( value ) {
			case VIdent(i): classes = [i];
			case VGroup(vl): classes = [for( v in vl ) switch( v ) { case VIdent(i): i; default: return InvalidValue(); }];
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
					break;
				}
			if( !found ) currentSet.push(p);
		}
		handler.apply(obj,v);
		return Ok;
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
		var value : T = c.make(args, parent.obj);
		var p = value.dom;
		if( p == null )
			value.dom = p = new Properties<T>(value, cast c);
		if( attributes != null )
			p.initAttributes(attributes);
		return p;
	}

}