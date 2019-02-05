class Obj extends Components.MydivComponent implements domkit.Object {

	static var SRC =
	<mydiv class="foo" padding-left="$value" color="blue">
		@exampleText
		<custom(55) id="sub" custom-color="#ff0 0.5"/>
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

		var css = new domkit.CssStyle();
		css.add(new domkit.CssParser().parseSheet(".foo custom { padding-left : 50; }"));
		o.setStyle(css);

		trace(o.sub.paddingLeft); // 50
	}

}