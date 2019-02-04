@:uiComp("custom") @:parser(CustomParser)
class CustomComponent extends Components.MydivComponent {

	@:p(colorAlpha) public var customColor : { color : Int, alpha : Float };

	public function new( value : Int, parent ) {
		super(parent);
	}


}