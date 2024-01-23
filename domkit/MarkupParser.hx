package domkit;

using StringTools;

enum abstract MToken(Int) {
	var IGNORE_SPACES;
	var BEGIN;
	var BEGIN_NODE;
	var BEGIN_CODE;
	var CODE_IDENT;
	var CODE_BLOCK;
	var TAG_NAME;
	var BODY;
	var ATTRIB_NAME;
	var EQUALS;
	var ATTVAL_BEGIN;
	var ATTRIB_VAL;
	var ATTRIB_VAL_CODE;
	var CHILDS;
	var CLOSE;
	var WAIT_END;
	var WAIT_END_RET;
	var PCDATA;
	var HEADER;
	var COMMENT;
	var DOCTYPE;
	var CDATA;
	var ESCAPE;
	var ARGS;
	var MACRO_ID;
	var IF_COND;
}

typedef CodeExpr = #if macro haxe.macro.Expr #else String #end;

enum MarkupKind {
	Node( name : String );
	Text( text : String );
	CodeBlock( v : String );
	Macro( id : String );
	For( cond : String );
}

enum AttributeValue {
	RawValue( v : String );
	Code( v : CodeExpr );
}

typedef Markup = {
	var kind : MarkupKind;
	var pmin : Int;
	var pmax : Int;
	var ?arguments : Array<{ value : AttributeValue, pmin : Int, pmax : Int }>;
	var ?attributes : Array<{ name : String, value : AttributeValue, pmin : Int, vmin : Int, pmax : Int }>;
	var ?children : Array<Markup>;
	var ?condition : { cond : CodeExpr, pmin : Int, pmax : Int };
}

private typedef MarkupLoop = {
	var obj : Markup;
	var isBlock : Bool;
	var prevLoop : MarkupLoop;
}

class MarkupParser {

	static var escapes = {
		var h = new haxe.ds.StringMap();
		h.set("lt", "<");
		h.set("gt", ">");
		h.set("amp", "&");
		h.set("quot", '"');
		h.set("apos", "'");
		h;
	}

	var fileName : String;
	var filePos : Int;

	public var allowRawText : Bool = false;

	public function new() {
	}

	public function parse(str:String,fileName:String,filePos:Int) {
		var p : Markup = {
			kind : Node(null),
			pmin : 0,
			pmax : 0,
			children : [],
		};
		this.fileName = fileName;
		this.filePos = filePos;
		doParse(str, 0, p);
		return p;
	}

	function error( msg : String, position : Int, pmax = -1 ) : Dynamic {
		throw new Error(msg, filePos + position, pmax < 0 ? -1 : filePos + pmax);
		return null;
	}

	function parseAttr( val : String, start : Int ) {
		var v = StringTools.trim(val);
		if( v.length == 0 || v.charCodeAt(0) != "$".code )
			return RawValue(val);
		if( v.charCodeAt(1) == "{".code && v.charCodeAt(v.length-1) == "}".code )
			v = v.substr(2,v.length - 3);
		else
			v = v.substr(1);
		start += val.indexOf(v);
		return Code(parseCode(v, start));
	}

	function parseCode( v : String, start : Int ) {
		#if macro
		var e = try {
			var pos = haxe.macro.Context.makePosition({ min : filePos + start, max : filePos + start + v.length, file : fileName });
			haxe.macro.Context.parseInlineString(v,pos);
		} catch( e : Dynamic ) {
			// fallback for attr={x:v,y:v}
			try {
				var pos = haxe.macro.Context.makePosition({ min : filePos + start - 1, max : filePos + start + v.length + 1, file : fileName });
				haxe.macro.Context.parseInlineString("{"+v+"}",pos);
			} catch( _ : Dynamic )
				error("" + e, start, start + v.length);
		}
		switch( e.expr ) {
		case EConst(CIdent(i)) if( i.length != v.length ):
			// fallback for https://github.com/HaxeFoundation/haxe/issues/11368
			var e2 = try haxe.macro.Context.parseInlineString("{"+v+"}",haxe.macro.Context.makePosition({ min : filePos + start - 1, max : filePos + start + v.length + 1, file : fileName })) catch( e : Dynamic ) null;
			if( e2 != null && e2.expr.match(EObjectDecl(_)) )
				e = e2;
		default:
		}
		return e;
		#else
		return v;
		#end
	}

	function doParse(str:String, p:Int = 0, ?parent:Markup):Int {
		var obj : Markup = null;
		var state = BEGIN;
		var next = BEGIN;
		var aname = null;
		var start = 0;
		var nsubs = 0;
		var nbrackets = 0;
		var nbraces = 0;
		var nparents = 0;
		var attr_start = 0;
		var prevObj = null;
		var c = str.fastCodeAt(p);
		var buf = new StringBuf();
		// need extra state because next is in use
		var escapeNext = BEGIN;
		var attrValQuote = -1;
		var parentCount = 0;
		var currentLoop : MarkupLoop = null;
		inline function addChild(m:Markup) {
			m.pmin += filePos;
			m.pmax += filePos;
			if( currentLoop != null ) {
				currentLoop.obj.children.push(m);
				if( !currentLoop.isBlock )
					currentLoop = currentLoop.prevLoop;
			} else {
				parent.children.push(m);
				nsubs++;
			}
		}
		var r_prefix = ~/^([a-z]+)/;
		var r_string = ~/^['"]([^'"]*)['"]$/;
		function emitCode() {
			var fullText = buf.toString();
			var text = StringTools.trim(fullText);
			if( text.length == 0 )
				return;
			start += fullText.indexOf(text);
			if( r_prefix.match(text) ) {
				switch( r_prefix.matched(1) ) {
				case "for":
					var cond = r_prefix.matchedRight();
					var isBlock = false;
					if( StringTools.endsWith(cond,"{") ) {
						isBlock = true;
						cond = cond.substr(0,-1);
					}
					var obj = {
						kind : For(cond),
						pmin : start,
						pmax : start + text.length,
						children : [],
					};
					addChild(obj);
					currentLoop = { prevLoop : currentLoop, isBlock : isBlock, obj : obj };
					return;
				}
			} else if( text == "}" && currentLoop != null && currentLoop.isBlock ) {
				currentLoop = currentLoop.prevLoop;
				return;
			}
			if( !allowRawText ) {
				error("Unsupported code block", start, start + text.length);
				return;
			}
			addChild({
				kind : Text(text),
				pmin : start,
				pmax : start + text.length,
				children : [],
			});
		}
		inline function addNodeArg(last) {
			var base = str.substr(start, p - start);
			var arg = StringTools.trim(base);
			if( arg == "" ) {
				if( !last || obj.arguments.length > 0 )
					error("Empty argument", start, p + 1);
				start = p + 1;
				return;
			}
			start += base.indexOf(arg);
			if( r_string.match(arg) ) {
				obj.arguments.push({ value : RawValue(arg.substr(1,arg.length - 2)), pmin : filePos + start + 1, pmax : filePos + start + arg.length - 1 });
			} else {
				obj.arguments.push({ value : Code(parseCode(arg,start)), pmin : filePos + start, pmax : filePos + start + arg.length });
			}
			start = p + 1;
		}
		while (!StringTools.isEof(c)) {
			switch(state) {
				case IGNORE_SPACES:
					switch(c)
					{
						case
							'\n'.code,
							'\r'.code,
							'\t'.code,
							' '.code:
						default:
							state = next;
							continue;
					}
				case BEGIN:
					switch(c)
					{
						case '<'.code:
							state = IGNORE_SPACES;
							next = BEGIN_NODE;
						default:
							start = p;
							state = PCDATA;
							continue;
					}
				case PCDATA:
					switch( c ) {
					case '<'.code, '$'.code:
						buf.addSub(str, start, p - start);
						emitCode();
						buf = new StringBuf();
						if( c == '$'.code ) {
							start = p + 1;
							state = BEGIN_CODE;
						} else {
							state = IGNORE_SPACES;
							next = BEGIN_NODE;
						}
					case '@'.code:
						if( StringTools.trim(str.substr(start, p - start)) == "" ) {
							buf.addSub(str, start, p - start);
							state = MACRO_ID;
							start = p + 1;
						}
					case '/'.code, '*'.code:
						if( p > start && str.charCodeAt(p-1) == '/'.code ) {
							buf.addSub(str, start, p - 1 - start);
							if( c == '/'.code ) {
								while( true ) {
									c = str.fastCodeAt(p++);
									if( StringTools.isEof(c) || c == '\n'.code ) break;
								}
								start = p;
							} else {
								start = p - 1;
								var end = false;
								while( true ) {
									c = str.fastCodeAt(p++);
									if( StringTools.isEof(c) ) error("Unclosed comment", start, start + 2);
									if( c == '*'.code ) end = true else if( end && c == '/'.code ) break; else end = false;
								}
								start = p;
							}
						}
					}
				case MACRO_ID:
					if( !isValidChar(c) ) {
						var id = str.substr(start, p - start);
						var m : Markup = {
							kind : Macro(id),
							pmin : start,
							pmax : p,
						};
						addChild(m);
						if( c == '('.code ) {
							state = ARGS;
							prevObj = obj;
							obj = m;
							obj.arguments = [];
							start = p + 1;
							nparents = 1;
							nbrackets = nbraces = 0;
						} else {
							start = p;
							state = PCDATA;
							buf = new StringBuf();
							continue;
						}
					}
				case CDATA:
					if (c == ']'.code && str.fastCodeAt(p + 1) == ']'.code && str.fastCodeAt(p + 2) == '>'.code)
					{
						var child : Markup = {
							kind : Text(str.substr(start, p - start)),
							pmin : start,
							pmax : p,
						};
						addChild(child);
						p += 2;
						state = BEGIN;
					}
				case BEGIN_NODE:
					switch(c)
					{
						case '!'.code:
							if (str.fastCodeAt(p + 1) == '['.code)
							{
								p += 2;
								if (str.substr(p, 6).toUpperCase() != "CDATA[")
									error("Expected <![CDATA[", p);
								p += 5;
								state = CDATA;
								start = p + 1;
							}
							else if (str.fastCodeAt(p + 1) == 'D'.code || str.fastCodeAt(p + 1) == 'd'.code)
							{
								if(str.substr(p + 2, 6).toUpperCase() != "OCTYPE")
									error("Expected <!DOCTYPE", p);
								p += 8;
								state = DOCTYPE;
								start = p + 1;
							}
							else if( str.fastCodeAt(p + 1) != '-'.code || str.fastCodeAt(p + 2) != '-'.code )
								error("Expected <!--", p);
							else
							{
								p += 2;
								state = COMMENT;
								start = p + 1;
							}
						case '?'.code:
							state = HEADER;
							start = p;
						case '/'.code:
							if( parent == null )
								error("Expected node name", p);
							start = p + 1;
							state = IGNORE_SPACES;
							next = CLOSE;
						default:
							state = TAG_NAME;
							start = p;
							continue;
					}
				case BEGIN_CODE:
					if( c == '{'.code ) {
						state = CODE_BLOCK;
						start = p + 1;
						nbraces = 1;
					} else if( !isValidChar(c) ) {
						error("Expected code identifier or block",p);
					} else {
						state = CODE_IDENT;
					}
				case CODE_BLOCK:
					if( c == '{'.code )
						nbraces++;
					else if( c == '}'.code ) {
						nbraces--;
						if( nbraces == 0 ) {
							addChild({
								kind : CodeBlock(str.substr(start,p - start)),
								pmin : start,
								pmax : p,
							});
							state = BEGIN;
						}
					}
				case CODE_IDENT:
					if (!isValidChar(c)) {
						addChild({
							kind : CodeBlock(str.substr(start,p - start)),
							pmin : start,
							pmax : p,
						});
						state = BEGIN;
						continue;
					}
				case TAG_NAME:
					if (!isValidChar(c))
					{
						if( p == start )
							error("Expected node name", p);
						obj = {
							kind : Node(str.substr(start, p - start)),
							pmin : start,
							pmax : p,
							arguments : [],
							attributes : [],
							children : [],
						};
						addChild(obj);
						if( c == '('.code ) {
							state = ARGS;
							next = BODY;
							start = p + 1;
							nparents = 1;
							nbrackets = nbraces = 0;
						} else {
							state = IGNORE_SPACES;
							next = BODY;
							continue;
						}
					}
				case BODY:
					switch(c)
					{
						case '/'.code:
							state = WAIT_END;
						case '>'.code:
							state = CHILDS;
						default:
							state = ATTRIB_NAME;
							start = p;
							continue;
					}
				case ATTRIB_NAME:
					if (!isValidChar(c))
					{
						var tmp;
						if( start == p )
							error("Expected attribute name", p);
						tmp = str.substr(start,p-start);
						aname = tmp;
						for( a in obj.attributes )
							if( a.name == aname )
								error("Duplicate attribute '" + aname + "'", p);
						attr_start = start;
						state = IGNORE_SPACES;
						next = aname == "if" ? IF_COND : EQUALS;
						continue;
					}
				case EQUALS:
					switch(c) {
						case '='.code:
							state = IGNORE_SPACES;
							next = ATTVAL_BEGIN;
						case ' '.code, '\n'.code, '\t'.code, '\r'.code, '>'.code, '/'.code:
							obj.attributes.push({ name : aname, value : RawValue("true"), pmin : attr_start + filePos, vmin : attr_start + filePos, pmax : p + filePos });
							state = IGNORE_SPACES;
							next = BODY;
							continue;
						default:
							if( isValidChar(c) ) {
								obj.attributes.push({ name : aname, value : RawValue("true"), pmin : attr_start + filePos, vmin : attr_start + filePos, pmax : p + filePos });
								state = BODY;
								continue;
							}
							error("Expected =", p);
					}
				case IF_COND:
					switch( c ) {
					case '('.code:
						parentCount++;
					case ')'.code:
						parentCount--;
						if( parentCount == 0 ) {
							var code = str.substr(start + 2, p - start - 1);
							if( obj.condition != null ) error("Duplicate condition", start);
							obj.condition = { cond : parseCode(code, start+2), pmin : start + filePos + 2, pmax : p + filePos + 1 };
							state = BODY;
						}
					default:
					}
				case ATTVAL_BEGIN:
					switch(c)
					{
						case '"'.code | '\''.code:
							buf = new StringBuf();
							state = ATTRIB_VAL;
							start = p + 1;
							attrValQuote = c;
						case '{'.code:
							state = ATTRIB_VAL_CODE;
							start = p + 1;
							nbraces = 1;
						default:
							error("Expected \"", p);
					}
				case ATTRIB_VAL:
					switch (c) {
						case '&'.code:
							buf.addSub(str, start, p - start);
							state = ESCAPE;
							escapeNext = ATTRIB_VAL;
							start = p + 1;
						case '>'.code | '<'.code:
							// HTML allows these in attributes values
							error("Invalid unescaped " + String.fromCharCode(c) + " in attribute value", p);
						case _ if (c == attrValQuote):
							buf.addSub(str, start, p - start);
							var val = buf.toString();
							buf = new StringBuf();
							obj.attributes.push({ name : aname, value : parseAttr(val,start), pmin : attr_start + filePos, vmin : start + filePos, pmax : p + filePos });
							state = IGNORE_SPACES;
							next = BODY;
					}
				case ATTRIB_VAL_CODE:
					switch( c ) {
					case '{'.code:
						nbraces++;
					case '}'.code:
						nbraces--;
						if( nbraces == 0 ) {
							obj.attributes.push({ name : aname, value : Code(parseCode(str.substr(start, p-start),start)), pmin : attr_start + filePos, vmin : start + filePos, pmax : p + filePos });
							state = IGNORE_SPACES;
							next = BODY;
						}
					}
				case ARGS:
					switch( c ) {
					case ")".code:
						nparents--;
						if( nparents == 0 ) {
							addNodeArg(true);
							state = next;
							if( state == BODY ) {
								state = IGNORE_SPACES;
								next = BODY;
							} else
								obj = prevObj;
						}
					case '('.code:
						nparents++;
					case '{'.code:
						nbraces++;
					case '['.code:
						nbrackets++;
					case '}'.code:
						nbraces--;
					case ']'.code:
						nbrackets--;
					case ','.code if( nparents == 1 && nbrackets == 0 && nbraces == 0 ):
						addNodeArg(false);
					}
				case CHILDS:
					p = doParse(str, p, obj);
					start = p;
					state = BEGIN;
				case WAIT_END:
					switch(c)
					{
						case '>'.code:
							state = BEGIN;
						default :
							error("Expected >", p);
					}
				case WAIT_END_RET:
					switch(c)
					{
						case '>'.code:
							if( currentLoop != null )
								error("Unclosed loop", currentLoop.obj.pmin - filePos, currentLoop.obj.pmax - filePos);
							return p;
						default :
							error("Expected >", p);
					}
				case CLOSE:
					if (!isValidChar(c))
					{
						if( start == p )
							error("Expected node name", p);

						var v = str.substr(start,p - start);
						var ok = true;
						if( parent == null )
							ok = false;
						else switch( parent.kind ) {
						case Node(name) if( name != null && v == name.split(":")[0] ): // ok
						case Node(name) if( name != null ):
							error("Unclosed node <" + name.split(":")[0] + ">", parent.pmin - filePos, parent.pmax - filePos);
						default:
							ok = false;
						}
						if( !ok )
							error('Unexpected </$v>', p);
						state = IGNORE_SPACES;
						next = WAIT_END_RET;
						continue;
					}
				case COMMENT:
					if (c == '-'.code && str.fastCodeAt(p +1) == '-'.code && str.fastCodeAt(p + 2) == '>'.code)
					{
						//addChild(Xml.createComment(str.substr(start, p - start)));
						p += 2;
						state = BEGIN;
					}
				case DOCTYPE:
					if(c == '['.code)
						nbrackets++;
					else if(c == ']'.code)
						nbrackets--;
					else if (c == '>'.code && nbrackets == 0)
					{
						//addChild(Xml.createDocType(str.substr(start, p - start)));
						state = BEGIN;
					}
				case HEADER:
					if (c == '?'.code && str.fastCodeAt(p + 1) == '>'.code)
					{
						p++;
						var str = str.substr(start + 1, p - start - 2);
						//addChild(Xml.createProcessingInstruction(str));
						state = BEGIN;
					}
				case ESCAPE:
					if (c == ';'.code)
					{
						var s = str.substr(start, p - start);
						if (s.fastCodeAt(0) == '#'.code) {
							var c = s.fastCodeAt(1) == 'x'.code
								? Std.parseInt("0" +s.substr(1, s.length - 1))
								: Std.parseInt(s.substr(1, s.length - 1));
							buf.addChar(c);
						} else if (!escapes.exists(s)) {
							error("Undefined entity: " + s, p);
							buf.add('&$s;');
						} else {
							buf.add(escapes.get(s));
						}
						start = p + 1;
						state = escapeNext;
					} else if (!isValidChar(c) && c != "#".code) {
						error("Invalid character in entity: " + String.fromCharCode(c), p);
						buf.addChar("&".code);
						buf.addSub(str, start, p - start);
						p--;
						start = p + 1;
						state = escapeNext;
					}
			}
			c = str.fastCodeAt(++p);
		}

		if (state == BEGIN)
		{
			start = p;
			state = PCDATA;
		}

		if (state == PCDATA)
		{
			switch( parent.kind ) {
			case Node(name) if( name != null ):
				error("Unclosed node <" + name + ">", p);
			default:
			}
			if (p != start || nsubs == 0) {
				buf.addSub(str, start, p-start);
				emitCode();
			}
			if( currentLoop != null )
				error("Unclosed loop", currentLoop.obj.pmin - filePos);
			return p;
		}

		error("Unexpected end", p);
		return p;
	}

	static inline function isValidChar(c) {
		return (c >= 'a'.code && c <= 'z'.code) || (c >= 'A'.code && c <= 'Z'.code) || (c >= '0'.code && c <= '9'.code) || c == ':'.code || c == '.'.code || c == '_'.code || c == '-'.code;
	}
}
