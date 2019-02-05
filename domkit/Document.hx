package domkit;

class Document<T> {

	public var style(default,null) : CssStyle;
	public var root(default,null) : Element<T>;

	public function new(root) {
		this.root = root;
	}

	public function setStyle( s : CssStyle ) {
		if( s == null ) s = new CssStyle();
		style = s;
		@:privateAccess s.applyStyle(root,true);
	}

	public inline function get( e : T ) {
		return root.get(e);
	}

	public function sync() {
		if( style != null ) @:privateAccess style.applyStyle(root,false);
	}

	public function remove() {
		root.remove();
	}

}