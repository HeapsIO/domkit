import CustomParser;

class InitComponents {

	static function init() {
		domkit.Macros.registerComponent(macro : Components.BaseComponent);
		domkit.Macros.registerComponent(macro : Components.DivComponent);
		domkit.Macros.registerComponent(macro : Components.CustomComponent);
	}

}