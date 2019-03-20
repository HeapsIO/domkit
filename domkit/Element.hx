package domkit;

enum SetAttributeResult {
	Ok;
	Unknown;
	Unsupported;
	InvalidValue( ?msg : String );
}

class Element<T> {

	public var id(default,null) : String;
	public var obj(default,null) : T;
	public var component(default,null) : Component<T,Dynamic>;
	public var parent(default,null) : Element<T>;
	public var children(default,null) : Array<Element<T>> = [];
	public var hover(default,set) : Bool = false;
	var classes : Array<String>;
	var style : Array<{ p : Property, value : Any }> = [];
	var currentSet : Array<Property> = [];
	var needStyleRefresh : Bool = true;

	public function new(obj,component,?parent) {
		this.obj = obj;
		this.component = component;
		this.parent = parent;
		if( parent != null ) parent.children.push(this);
	}

	public function remove() {
		if( parent != null ) {
			parent.children.remove(this);
			parent = null;
		}
		removeElement(this);
	}

	public function addClass( c : String ) {
		if( classes == null )
			classes = [];
		if( classes.indexOf(c) < 0 ) {
			classes.push(c);
			needStyleRefresh = true;
		}
	}

	public function removeClass( c : String ) {
		if( classes.remove(c) ) {
			needStyleRefresh = true;
			if( classes.length == 0 ) classes = null;
		}
	}

	public function toggleClass( c : String ) {
		if( classes == null )
			classes = [c];
		else if( classes.remove(c) ) {
			if( classes.length == 0 ) classes = null;
		} else
			classes.push(c);
		needStyleRefresh = true;
	}

	public function get( obj : T ) {
		if( this.obj == obj ) return this;
		for( c in children ) {
			var v = c.get(obj);
			if( v != null ) return v;
		}
		return null;
	}

	function set_hover(b) {
		if( hover == b ) return b;
		needStyleRefresh = true;
		return hover = b;
	}

	function initStyle( p : String, value : Dynamic ) {
		style.push({ p : Property.get(p), value : value });
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
			if( ret != Ok )
				Sys.println(component.name+"."+a+"> "+ret);
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
					needStyleRefresh = true;
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
			needStyleRefresh = true;
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

	public static dynamic function getParent<T>( e : T ) : T {
		return null;
	}

	public static dynamic function addElement( e : Element<Dynamic>, to : Element<Dynamic> ) {
	}

	public static dynamic function removeElement( e : Element<Dynamic> ) {
	}

	static var pclass = Property.get("class");
	static var pid = Property.get("id");
	public static function create<BaseT,T:BaseT>( comp : String, attributes : haxe.DynamicAccess<String>, ?parent : Element<BaseT>, ?value : T, ?args : Array<Dynamic> ) {
		var c = Component.get(comp);
		var e;
		if( value == null )
			value = c.make(args, parent == null ? null : parent.obj);
		if( c.hasDocument && parent != null ) {
			e = ((value:Dynamic).document : Document<BaseT>).root;
			e.component = cast c;
			e.parent = parent;
			if( parent != null ) parent.children.push(e);
		} else
			e = new Element<BaseT>(value, cast c, parent);
		if( attributes != null ) e.initAttributes(attributes);
		if( parent != null && value != null ) addElement(e, parent);
		return e;
	}

}