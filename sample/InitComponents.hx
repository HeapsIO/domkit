import CustomParser;

class InitComponents {

	static function init() {
		domkit.Macros.registerComponentsPath("Components.$Component");
		domkit.Macros.registerComponentsPath("$Component");
		domkit.Macros.customTextParser = customTextParser;
	}

	static function customTextParser( id : String, args : Array<haxe.macro.Expr>, pos : haxe.macro.Expr.Position ) : haxe.macro.Expr {
		var text : haxe.macro.Expr = { expr : EField(macro Test,id), pos : pos };
		if( args != null )
			for( a in args )
				text = macro $text + $a;
		return text;
	}

}