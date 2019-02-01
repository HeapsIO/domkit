@:uiComp("custom") @:parser(CustomParser)
class CustomComponent extends Components.MydivComponent {

	@:p(colorAlpha) public var customColor : { color : Int, alpha : Float };

}