package domkit;

class Builder<T:domkit.Model<T>> {

	static var IS_EMPTY = ~/^[ \r\n\t]*$/;

	public var warnings : Array<Error> = [];
	var path : Array<String> = [];
	var data : Dynamic;

	public function new() {
	}

	function warn( msg : String, pmin : Int, pmax = -1 ) {
		warnings.push(new Error(path.join(".")+": "+msg,pmin,pmax));
	}

	public function build( src : String, ?data : {} ) {
		this.data = data;
		var x = new MarkupParser().parse(src,"source",0);
		return buildRec(x, null);
	}

	function evalArg( v : domkit.MarkupParser.AttributeValue, min : Int, max : Int ) : Dynamic {
		return switch( v ) {
		case Code(code):
			if( !~/^[A-Za-z0-9_\.]+$/.match(code) ) {
				warn("Unsupported complex code attribute", min, max);
				return null;
			}
			var path = code.split(".");
			var value : Dynamic = data;
			for( v in path )
				value = Reflect.field(value,v);
			return value;
		case RawValue(v):
			throw "TODO";
		}
	}

	function makeDom( name : String, args : Array<Dynamic>, parent : Properties<T> ) : Properties<T> {
		throw name;
		return null;
	}

	function buildRec( x : MarkupParser.Markup, parent : Properties<T> ) : Properties<T> {
		var inst = null;
		switch( x.kind ) {
		case Text(txt):
			inst = makeDom("text",[],parent);
			if( inst != null ) inst.setAttribute("text", VString(txt));
		case Node(null):
			var c = x.children[0];
			if( c == null )
				c = { kind : Text(""), pmin : 0, pmax : 0 };
			if( x.children.length > 1 )
				warn("Ignored multiple nodes", x.children[1].pmin, x.children[x.children.length-1].pmax);
			return buildRec(c, parent);
		case Node(name):
			path.push(name);
			var args = [for( v in x.arguments ) evalArg(v.value, v.pmin, v.pmax)];
			inst = makeDom(name, args, parent);
			if( inst == null )
				warn("Unknown component "+name, x.pmin, x.pmin + name.length);
			var css = new CssParser();
			for( a in x.attributes ) {
				if( inst == null ) continue;
				switch( a.value ) {
				case RawValue(v):
					var css = try css.parseValue(v) catch( e : Error ) {
						path.push(a.name);
						warn("Invalid attribute value '"+v+"' ("+e.message+")", e.pmin + a.vmin, a.pmax);
						path.pop();
						continue;
					}
					switch( inst.setAttribute(a.name.toLowerCase(),css) ) {
					case Ok:
					case Unknown:
						path.push(a.name);
						warn("Unknown attribute", a.pmin, a.pmin+a.name.length);
						path.pop();
					case Unsupported:
						warn("Unsupported attribute "+a+" in", a.pmin, a.pmin+a.name.length);
					case InvalidValue(msg):
						path.push(a.name);
						warn("Invalid attribute value"+(msg == null ? "" : " ("+msg+") for"), a.vmin, a.pmax);
						path.pop();
					}
				case Code(_):
					var value = evalArg(a.value, a.vmin, a.pmax);
					// TODO
				}
			}
			for( e in x.children )
				buildRec(e, inst == null ? parent : inst);
			path.pop();
		case CodeBlock(code):
			warn("Unsupported code block", x.pmin, x.pmax);
		case Macro(_):
			warn("Unsupported macro", x.pmin, x.pmax);
		}
		return inst;
	}

}
