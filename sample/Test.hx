import domkit.Builder;

class Obj extends Components.MydivComponent implements domkit.Object {

	static var SRC =
	<mydiv class="foo" padding-left="$value" color="blue">
		@exampleText("!")
		<custom(55) public id="sub" custom-color="#ff0 0.5" active/>
	</mydiv>

	public function new(value,?parent) {
		super(parent);
		initComponent(); // create the component tree
	}

}

class Test {

	public static var exampleText = "Hello World";

	static function main() {
		var o = new Obj(55);
		trace(o.color); // Blue
		trace(o.paddingLeft); // 55
		trace(o.sub.paddingLeft); // 0
		trace( cast(o.document.root.children[0].obj,Components.TextComponent).text ); // "Hello World!"

		var css = new domkit.CssStyle();
		css.add(new domkit.CssParser().parseSheet(sys.io.File.getContent("test.css")));
		o.setStyle(css);

		trace(o.sub.paddingLeft); // 50

		var elt = o.document.get(o.sub);
		elt.addClass("over");
		o.document.sync();
		trace(o.sub.paddingLeft); // 60

	}

}