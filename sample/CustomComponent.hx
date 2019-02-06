@:uiComp("custom") @:parser(CustomParser)
class CustomComponent extends Components.MydivComponent {

	@:p(colorAlpha) public var customColor : { color : Int, alpha : Float };
	@:p var active : Bool;

	public function new( value : Int, parent ) {
		super(parent);
	}


}