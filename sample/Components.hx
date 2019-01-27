
@:uiComp("object") /* top level component should always be named "object" */
class BaseComponent {

	@:p var name : String; // should be declared in BaseComponent to allow custom naming

	public function new(?parent:BaseComponent) {
	}
}

enum Color {
	Red;
	Green;
	Blue;
}

typedef Padding = { left : Int, right : Int, top : Int, bottom : Int };

@:uiComp("mydiv")
class DivComponent extends BaseComponent {
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

@:uiComp("custom") @:parser(CustomParser)
class CustomComponent extends DivComponent {

	@:p(colorAlpha) public var customColor : { color : Int, alpha : Float };

}