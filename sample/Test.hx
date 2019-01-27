class Obj extends Components.DivComponent implements uikit.Object {

	static var SRC =
	<mydiv class="foo" padding-left="$value" color="blue">
		<custom name="sub" custom-color="#ff0 0.5"/>
	</mydiv>
	;

	public function new(value,?parent) {
		super(parent);
		initComponent(); // create the component tree
	}

}

class Test {

	static function main() {
		var o = new Obj(55);
		trace(o.color); // Blue
		trace(o.paddingLeft); // 55
		trace(o.sub.paddingLeft); // 0

		var css = new uikit.CssStyle();
		css.add(new uikit.CssParser().parseSheet(".foo custom { padding-left : 50; }"));
		o.setStyle(css);

		trace(o.sub.paddingLeft); // 50
	}

}