import CustomParser;

class InitComponents {

	static function init() {
		uikit.Macros.registerComponent(macro : Components.BaseComponent);
		uikit.Macros.registerComponent(macro : Components.DivComponent);
		uikit.Macros.registerComponent(macro : Components.CustomComponent);
	}

}