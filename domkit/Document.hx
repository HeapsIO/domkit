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

	public function add<T2:{public var document:Document<T>;} & T>( v : T2 ) {
		var elt = v.document.root;
		if( elt.parent != null ) throw "Already added";
		var parent = Element.getParent(v);
		var parentElt = get(parent);
		parentElt.children.push(v.document.root);
		@:privateAccess elt.parent = parentElt;
		@:privateAccess elt.needStyleRefresh = true;
	}

}