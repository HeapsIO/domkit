
@:uiComp("base")
class BaseComponent implements domkit.Model<BaseComponent> implements domkit.Object {

	// these are minimal fields required by domkit.Model for all components
	var children : Array<BaseComponent> = [];
	public var dom : domkit.Properties<BaseComponent>;
	public var parent : BaseComponent;
	public function getChildren() return children;

	// constructors should always take the parent component as optional last argument
	public function new(?parent:BaseComponent) {
		if( parent != null ) {
			this.parent = parent;
			parent.children.push(this);
		}
		initComponent();
	}

	public function remove() {
		if( parent != null ) {
			parent.children.remove(this);
			parent = null;
		}
	}

}

enum Color {
	Red;
	Green;
	Blue;
}

typedef Padding = { left : Int, right : Int, top : Int, bottom : Int };

@:uiComp("text")
class TextComponent extends BaseComponent {

	@:p(string) public var text : String;

}

@:uiComp("mydiv")
class MydivComponent extends BaseComponent {
	@:p public var paddingLeft : Int;
	@:p public var paddingRight : Int;
	@:p public var paddingTop : Int;
	@:p public var paddingBottom : Int;
	@:p public var color : Color;
	@:p(box) var padding(never,set) : Padding;

	function set_padding(v:Padding) {
		if( v == null ) {
			paddingLeft = paddingRight = paddingBottom = paddingTop = 0;
		} else {
			paddingLeft = v.left;
			paddingRight = v.right;
			paddingTop = v.top;
			paddingBottom = v.bottom;
		}
		return v;
	}

}
