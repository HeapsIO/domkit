import CustomParser;

class InitComponents {

	static function init() {
		domkit.Macros.registerComponentsPath("Components.$Component");
		domkit.Macros.registerComponentsPath("$Component");
		domkit.Macros.processMacro = processMacro;
		#if (haxe_ver >= 5)
		haxe.macro.Context.onAfterInitMacros(checkCSS);
		#else
		checkCSS();
		#end
	}

	static function checkCSS() {
		domkit.Macros.checkCSS("test.css");
	}

	static function processMacro( id : String, args : Array<haxe.macro.Expr>, pos : haxe.macro.Expr.Position ) : domkit.MarkupParser.Markup {
		var text : haxe.macro.Expr = { expr : EField(macro Test,id), pos : pos };
		if( args != null )
			for( a in args )
				text = macro $text + $a;
		return {
			pmin : 0,
			pmax : 0,
			kind : Node("text"),
			attributes : [{
				pmin : 0,
				pmax : 0,
				name : "text",
				vmin : 0,
				value : Code(text),
			}]
		};
	}

}