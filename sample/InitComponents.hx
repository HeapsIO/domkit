import CustomParser;

class InitComponents {

	static function init() {
		domkit.Macros.registerComponentsPath("Components.$Component");
		domkit.Macros.registerComponentsPath("$Component");
	}

}