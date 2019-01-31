package domkit;

class Document<T> {

	public var elements : Array<Element<T>> = [];
	public var style(default,null) : CssStyle;
	public var root(get,never) : Element<T>;

	public function new() {
	}

	inline function get_root() {
		return elements[0];
	}

	public function setStyle( s : CssStyle ) {
		if( s == null ) s = new CssStyle();
		style = s;
		for( e in elements )
			@:privateAccess s.applyStyle(e,true);
	}

	public function remove() {
		for( e in elements )
			e.remove();
	}

}