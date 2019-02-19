package domkit;
import domkit.CssValue;

enum Token {
	TIdent( i : String );
	TString( s : String );
	TInt( i : Int );
	TFloat( f : Float );
	TDblDot;
	TSharp;
	TPOpen;
	TPClose;
	TExclam;
	TComma;
	TEof;
	TPercent;
	TSemicolon;
	TBrOpen;
	TBrClose;
	TDot;
	TSpaces;
	TSlash;
	TStar;
	TBkOpen;
	TBkClose;
}

class CssClass {
	public var parent : Null<CssClass>;
	public var component : Null<Component<Dynamic,Dynamic>>;
	public var className : Null<String>;
	public var pseudoClass : Null<String>;
	public var id : Null<String>;
	public function new() {
	}
}

typedef CssSheet = Array<{ classes : Array<CssClass>, style : Array<{ p : Property, value : CssValue, pmin : Int, vmin : Int, pmax : Int }> }>;

class CssParser {

	var css : String;
	var pos : Int;
	var tokenStart : Int;
	var valueStart : Int;

	var spacesTokens : Bool;
	var tokens : Array<Token>;
	public var warnings : Array<{ pmin : Int, pmax : Int, msg : String }>;

	public function new() {
	}

	function error( msg : String ) {
		throw new Error(msg,pos);
	}

	function unexpected( t : Token ) : Dynamic {
		var str = tokenString(t);
		throw new Error("Unexpected " + str, pos - str.length, pos);
		return null;
	}

	function tokenString( t : Token ) {
		return switch (t) {
			case TIdent(i): i;
			case TString(s): '"'+s+'"';
			case TInt(i): ""+i;
			case TFloat(f): ""+f;
			case TDblDot: ":";
			case TSharp: "#";
			case TPOpen: "(";
			case TPClose: ")";
			case TExclam: "!";
			case TComma: ",";
			case TEof: "EOF";
			case TPercent: "%";
			case TSemicolon: ",";
			case TBrOpen: "{";
			case TBrClose: "}";
			case TDot: ".";
			case TSpaces: "space";
			case TSlash: "/";
			case TStar: "*";
			case TBkOpen: "[";
			case TBkClose: "]";
		};
	}

	function expect( t : Token ) {
		var tk = readToken();
		if( tk != t ) unexpected(tk);
	}

	inline function push( t : Token ) {
		tokens.push(t);
	}

	function isToken(t) {
		var tk = readToken();
		if( tk == t ) return true;
		push(tk);
		return false;
	}

	public function parse( css : String ) {
		this.css = css;
		pos = 0;
		tokens = [];
		warnings = [];
		return parseStyle(TEof);
	}

	public function parseValue( valueStr : String ) {
		this.css = valueStr;
		pos = 0;
		tokens = [];
		warnings = [];
		if( isToken(TEof) )
			return VString("");
		var v = readValue();
		expect(TEof);
		return v;
	}

	public static function valueStr(v) {
		return switch( v ) {
		case VIdent(i): i;
		case VString(s): '"' + s + '"';
		case VUnit(f, unit): f + unit;
		case VFloat(f): Std.string(f);
		case VInt(v): Std.string(v);
		case VHex(v,_): "#" + v;
		case VList(l):
			[for( v in l ) valueStr(v)].join(", ");
		case VGroup(l):
			[for( v in l ) valueStr(v)].join(" ");
		case VCall(f,args): f+"(" + [for( v in args ) valueStr(v)].join(", ") + ")";
		case VLabel(label, v): valueStr(v) + " !" + label;
		case VSlash: "/";
		case VArray(v, content): valueStr(v) + "[" + (content == null ? "" : valueStr(content)) + "]";
		}
	}

	function parseStyle( eof ) {
		var style = [];
		while( true ) {
			if( isToken(eof) )
				break;
			var name = readIdent();
			var start = tokenStart;
			expect(TDblDot);
			var value = readValue();
			var p = Property.get(name, false);
			if( p == null )
				warnings.push({ pmin : start, pmax : pos, msg : "Unknown property "+name });
			else
				style.push({ p : p, value : value, pmin : start, vmin : valueStart, pmax : pos });
			if( isToken(eof) )
				break;
			expect(TSemicolon);
		}
		return style;
	}

	public function parseSheet( css : String ) : CssSheet {
		this.css = css;
		pos = 0;
		tokens = [];
		warnings = [];
		var rules : CssSheet = [];
		while( true ) {
			if( isToken(TEof) )
				break;
			var classes = readClasses();
			expect(TBrOpen);
			rules.push({ classes : classes, style : parseStyle(TBrClose) });
		}
		return rules;
	}

	public function parseClasses( css : String ) {
		this.css = css;
		pos = 0;
		tokens = [];
		var c = readClasses();
		expect(TEof);
		return c;
	}

	// ----------------- class parser ---------------------------

	function readClasses() {
		var classes = [];
		while( true ) {
			spacesTokens = true;
			isToken(TSpaces); // skip
			var c = readClass(null);
			spacesTokens = false;
			if( c == null ) break;
			classes.push(c);
			if( !isToken(TComma) )
				break;
		}
		if( classes.length == 0 )
			unexpected(readToken());
		return classes;
	}

	function readClass( parent ) : CssClass {
		var c = new CssClass();
		c.parent = parent;
		var def = false;
		var last = null;
		while( true ) {
			var p = pos;
			var t = readToken();
			if( last == null )
				switch( t ) {
				case TStar: def = true;
				case TDot, TSharp, TDblDot: last = t;
				case TIdent(i):
					#if macro
					var comp = @:privateAccess Macros.loadComponent(i,p,this.pos);
					#else
					var comp = Component.get(i,true);
					#end
					if( comp == null ) error("Unknown component "+i);
					c.component = comp;
					def = true;
				case TSpaces:
					return def ? readClass(c) : null;
				case TBrOpen, TComma, TEof:
					push(t);
					break;
				default:
					unexpected(t);
				}
			else
				switch( t ) {
				case TIdent(i):
					switch( last ) {
					case TDot: c.className = i; def = true;
					case TSharp: c.id = i; def = true;
					case TDblDot: c.pseudoClass = i; def = true;
					default: unexpected(last);
					}
					last = null;
				default:
					unexpected(t);
				}
		}
		return def ? c : parent;
	}

	// ----------------- value parser ---------------------------

	function readIdent() {
		var t = readToken();
		return switch( t ) {
		case TIdent(i): i;
		default: unexpected(t);
		}
	}

	function readValue(?opt) : CssValue {
		var t = readToken();
		var start = tokenStart;
		var v = switch( t ) {
		case TSharp:
			var h = readHex();
			if( h.length == 0 )
				error("Invalid hex value");
			VHex(h,Std.parseInt("0x"+h));
		case TIdent(i):
			var start = pos;
			var c = next();
			if( isStrIdentChar(c) ) {
				do c = next() while( isIdentChar(c) || isNum(c) || isStrIdentChar(c) );
				pos--;
				i += css.substr(start, pos - start);
			} else
				pos--;
			VIdent(i);
		case TString(s):
			VString(s);
		case TInt(i):
			readValueUnit(i, i);
		case TFloat(f):
			readValueUnit(f, null);
		case TSlash:
			VSlash;
		default:
			if( !opt ) unexpected(t);
			push(t);
			null;
		};
		if( v != null ) v = readValueNext(v);
		valueStart = start;
		return v;
	}

	function readHex() {
		var start = pos;
		while( true ) {
			var c = next();
			if( (c >= "A".code && c <= "F".code) || (c >= "a".code && c <= "f".code) || (c >= "0".code && c <= "9".code) )
				continue;
			pos--;
			break;
		}
		return css.substr(start, pos - start);
	}

	function readValueUnit( f : Float, ?i : Int ) {
		var curPos = pos;
		var t = readToken();
		return switch( t ) {
		case TIdent(u) if( pos == curPos + u.length ):
			if( u == "px" )
				(i == null ? VFloat(f) : VInt(i)); // ignore "px" unit suffit
			else
				VUnit(f, u);
		case TPercent:
			VUnit(f, "%");
		default:
			push(t);
			if( i != null )
				VInt(i);
			else
				VFloat(f);
		};
	}

	function readValueNext( v : CssValue ) : CssValue {
		var t = readToken();
		return switch( t ) {
		case TPOpen:
			switch( v ) {
			case VIdent(i):
				switch( i ) {
				case "url":
					readValueNext(VCall("url",[VString(readUrl())]));
				default:
					var args = switch( readValue() ) {
					case VList(l): l;
					case x: [x];
					}
					expect(TPClose);
					readValueNext(VCall(i, args));
				}
			default:
				push(t);
				v;
			}
		case TBkOpen:
			var br = readValue(true);
			expect(TBkClose);
			return readValueNext(VArray(v, br));
		case TExclam:
			var t = readToken();
			switch( t ) {
			case TIdent(i):
				VLabel(i, v);
			default:
				unexpected(t);
			}
		case TComma:
			loopComma(v, readValue());
		default:
			push(t);
			var v2 = readValue(true);
			if( v2 == null )
				v;
			else
				loopNext(v, v2);
		}
	}

	function loopNext(v, v2) {
		return switch( v2 ) {
		case VGroup(l):
			l.unshift(v);
			v2;
		case VList(l):
			l[0] = loopNext(v, l[0]);
			v2;
		case VLabel(lab, v2):
			VLabel(lab, loopNext(v, v2));
		default:
			VGroup([v, v2]);
		};
	}

	function loopComma(v,v2) {
		return switch( v2 ) {
		case VList(l):
			l.unshift(v);
			v2;
		case VLabel(lab, v2):
			VLabel(lab, loopComma(v, v2));
		default:
			VList([v, v2]);
		};
	}

	// ----------------- lexer -----------------------

	inline function isSpace(c) {
		return (c == " ".code || c == "\n".code || c == "\r".code || c == "\t".code);
	}

	inline function isIdentChar(c) {
		return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || (c == "-".code) || (c == "_".code);
	}

	inline function isStrIdentChar(c) {
		return c == "/".code || c == ".".code;
	}

	inline function isNum(c) {
		return c >= "0".code && c <= "9".code;
	}

	inline function next() {
		return StringTools.fastCodeAt(css, pos++);
	}

	function readUrl() {
		var c0 = next();
		while( isSpace(c0) )
			c0 = next();
		var quote = c0;
		if( quote == "'".code || quote == '"'.code ) {
			pos--;
			switch( readToken() ) {
			case TString(s):
				var c0 = next();
				while( isSpace(c0) )
					c0 = next();
				if( c0 != ")".code )
					error("Invalid char " + String.fromCharCode(c0));
				return s;
			case tk:
				unexpected(tk);
			}

		}
		var start = pos - 1;
		while( true ) {
			if( StringTools.isEof(c0) )
				break;
			c0 = next();
			if( c0 == ")".code ) break;
		}
		return StringTools.trim(css.substr(start, pos - start - 1));
	}

	#if false
	function readToken( ?pos : haxe.PosInfos ) {
		var t = _readToken();
		haxe.Log.trace(t, pos);
		return t;
	}

	function _readToken() {
	#else
	function readToken() {
	#end
		var t = tokens.pop();
		if( t != null )
			return t;
		while( true ) {
			tokenStart = pos;
			var c = next();
			if( StringTools.isEof(c) )
				return TEof;
			if( isSpace(c) ) {
				if( spacesTokens ) {
					while( isSpace(next()) ) {
					}
					pos--;
					return TSpaces;
				}
				continue;
			}
			if( isNum(c) || c == '-'.code ) {
				var i = 0, neg = false;
				if( c == '-'.code ) { c = "0".code; neg = true; }
				do {
					i = i * 10 + (c - "0".code);
					c = next();
				} while( isNum(c) );
				if( c == ".".code ) {
					var f : Float = i;
					var k = 0.1;
					while( isNum(c = next()) ) {
						f += (c - "0".code) * k;
						k *= 0.1;
					}
					pos--;
					return TFloat(neg? -f : f);
				}
				pos--;
				return TInt(neg ? -i : i);
			}
			if( isIdentChar(c) ) {
				var pos = pos - 1;
				var isStr = false;
				do c = next() while( isIdentChar(c) || isNum(c) );
				this.pos--;
				return TIdent(css.substr(pos,this.pos - pos));
			}
			switch( c ) {
			case ":".code: return TDblDot;
			case "#".code: return TSharp;
			case "(".code: return TPOpen;
			case ")".code: return TPClose;
			case "!".code: return TExclam;
			case "%".code: return TPercent;
			case ";".code: return TSemicolon;
			case ".".code: return TDot;
			case "{".code: return TBrOpen;
			case "}".code: return TBrClose;
			case ",".code: return TComma;
			case "*".code: return TStar;
			case "[".code: return TBkOpen;
			case "]".code: return TBkClose;
			case "/".code:
				var start = pos - 1;
				if( (c = next()) != '*'.code ) {
					pos--;
					return TSlash;
				}
				while( true ) {
					while( (c = next()) != '*'.code ) {
						if( StringTools.isEof(c) ) {
							pos = start;
							error("Unclosed comment");
						}
					}
					c = next();
					if( c == "/".code ) break;
					if( StringTools.isEof(c) ) {
						pos = start;
						error("Unclosed comment");
					}
				}
				return readToken();
			case "'".code, '"'.code:
				var pos = pos;
				var k;
				while( (k = next()) != c ) {
					if( StringTools.isEof(k) ) {
						this.pos = pos;
						error("Unclosed string constant");
					}
					if( k == "\\".code ) {
						throw "todo";
						continue;
					}
				}
				return TString(css.substr(pos, this.pos - pos - 1));
			default:
			}
			pos--;
			error("Invalid char " + css.charAt(pos));
		}
		return null;
	}

	public function check( rules : CssParser.CssSheet, components : Array<Component<Dynamic,Dynamic>> ) {
		inline function error(msg,min,max) {
			warnings.push({ msg : msg, pmin : min, pmax : max });
		}
		for( r in rules ) {
			var comp = r.classes[0].component;
			var first = true;
			for( c in r.classes )
				if( c.component != comp ) {
					comp = null;
					break;
				}
			for( s in r.style ) {
				var handlers = [];
				if( comp != null ) {
					var h = comp.getHandler(s.p);
					if( h == null ) {
						error(comp.name+" does not handle property "+s.p.name, s.pmin, s.pmin + s.p.name.length);
						continue;
					}
					var cur = comp;
					while( cur.parent != null ) {
						var h2 = cur.parent.getHandler(s.p);
						if( h == h2 )
							cur = cur.parent;
						else
							break;
					}
					handlers.push({ c : cur, h : h });
				} else {
					for( c in components ) {
						var h = c.getHandler(s.p);
						if( h == null ) continue;
						for( h2 in handlers )
							if( h2.h == h ) {
								h = null;
								break;
							}
						if( h == null ) continue;
						handlers.push({ c : c, h : h });
					}
					if( handlers.length == 0 ) {
						error("No component handles property "+s.p.name, s.pmin, s.pmin + s.p.name.length);
						continue;
					}
				}
				var ok = false, msg = null;
				for( h in handlers ) {
					try {
						h.h.parser(s.value);
						ok = true;
						break;
					} catch( e : Property.InvalidProperty ) {
						if( e.message != null && msg == null )
							msg = e.message;
					}
				}
				if( ok ) continue;
				error("Invalid "+[for( h in handlers ) h.c.name].join("|")+"."+s.p.name+" value '"+valueStr(s.value)+"'"+(msg == null ? "" : '($msg)'), s.vmin, s.pmax);
			}
		}
	}

}
