@:uiComp("custom") @:parser(CustomParser)
class CustomComponent extends Components.MydivComponent {

	@:p(colorAlpha) public var customColor : { color : Int, alpha : Float };
	@:p var active : Bool;
	@:p(none) public var maxWidth : Null<Int>;

	public function new( value : Int, parent ) {
		super(parent);
		initComponent();
	}

	function set_maxWidth(v: Null<Int>) {
		trace("maxWidth = " + v);
		return this.maxWidth = v;
	}
}