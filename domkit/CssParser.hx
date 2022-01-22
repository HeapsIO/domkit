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
	TSuperior;
}

enum abstract PseudoClass(Int) {

	var None = 0;
	var HOver = 1;
	var FirstChild = 2;
	var LastChild = 4;
	var Odd = 8;
	var Even = 16;
	var Active = 32;
	var Disabled = 64;

	// set for some flags requiring children checks
	var NeedChildren = 128;

	inline function new(v:Int) {
		this = v;
	}

	public inline function toInt() return this;
	public inline function has( c : PseudoClass ) return this & c.toInt() != 0;

	@:op(a | b) inline function or( v : PseudoClass ) : PseudoClass {
		return new PseudoClass(this | v.toInt());
	}

}

enum abstract CssRelation(Int) {
	var None = 0;
	var ImmediateChildren = 1;
}

class CssClass {
	public var parent : Null<CssClass>;
	public var component : Null<Component<Dynamic,Dynamic>>;
	public var className : Null<String>;
	public var extraClasses : Null<Array<String>>;
	public var pseudoClasses : PseudoClass = None;
	public var id : Null<String>;
	public var relation : CssRelation = None;
	public function new() {
	}
}

typedef Transition = {
	var p : Property;
	var time : Float;
	var curve : Curve;
}

typedef CssSheet = Array<{
	var classes : Array<CssClass>;
	var style : Array<{ p : Property, value : CssValue, pmin : Int, vmin : Int, pmax : Int }>;
	var ?transitions : Array<Transition>;
 }>;


class Curve {
	public function new() {
	}
	public function interpolate( v : Float ) : Float {
		return v;
	}
}

class BezierCurve extends Curve {
	public var c1x : Float;
	public var c1y : Float;
	public var c2x : Float;
	public var c2y : Float;

	public function new(a:Float,b:Float,c:Float,d:Float) {
		super();
		this.c1x = a;
		this.c1y = b;
		this.c2x = c;
		this.c2y = d;
	}

	inline function bezier(c1:Float, c2:Float, t:Float) {
		var u = 1 - t;
		return c1 * 3 * t * u * u + c2 * 3 * t * t * u + t * t * t;
	}

	override function interpolate( p : Float ) {
		var minT = 0., maxT = 1., maxDelta = 0.001;
		while( maxT - minT > maxDelta ) {
			var t = (maxT + minT) * 0.5;
			var x = bezier(c1x, c2x, t);
			if( x > p )
				maxT = t;
			else
				minT = t;
		}

		var x0 = bezier(c1x, c2x, minT);
		var x1 = bezier(c1x, c2x, maxT);
		var dx = x1 - x0;
		var xfactor = dx == 0 ? 0.5 : (p - x0) / dx;

		var y0 = bezier(c1y, c2y, minT);
		var y1 = bezier(c1y, c2y, maxT);
		return y0 + (y1 - y0) * xfactor;
	}

}

class CssParser {

	var css : String;
	var pos : Int;
	var tokenStart : Int;
	var valueStart : Int;

	var spacesTokens : Bool;
	var tokens : Array<Token>;
	var warnedComponents : Map<String,Bool>;
	public var warnings : Array<{ pmin : Int, pmax : Int, msg : String }>;

	static var DEFAULT_CURVE : Curve = new BezierCurve(0.25,0.1,0.25,1.0);
	static var CURVES : Map<String,Curve> = [
		"ease" => DEFAULT_CURVE,
		"linear" => new Curve(),
		"ease-in" => new BezierCurve(0.42, 0, 1.0, 1.0),
		"ease-out" => new BezierCurve(0, 0, 0.58, 1.0),
		"ease-in-out" => new BezierCurve(0, 0, 0.58, 1.0),
	];

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
			case TSuperior: ">";
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

	function parseTransition( value : CssValue, pmin, pmax ) : Transition {
		inline function warn(msg) {
			warnings.push({ pmin : pmin, pmax : pmax, msg : msg });
		}
		var args = switch( value ) {
		case VGroup(l): l;
		default: [value];
		}
		if( args.length < 1 )
			return null;
		var pname = switch( args[0] ) {
		case VIdent(name): name;
		default:
			warn("Invalid transition");
			return null;
		};
		var p = Property.get(pname, false);
		if( p == null ) {
			warn("Unknown transition property "+pname);
			return null;
		}
		@:privateAccess p.hasTransition = true;
		var time = switch( args[1] ) {
		case null: 1.;
		case VUnit(v, "s"), VFloat(v): v;
		case VInt(i): i;
		default:
			warn("Invalid transition time "+valueStr(args[1]));
			return null;
		}
		var curve = DEFAULT_CURVE;
		switch( args[2] ) {
		case null:
		case VIdent(name):
			curve = CURVES.get(name);
			if( curve == null ) {
				warn("Unknown easing curve "+name);
				curve = DEFAULT_CURVE;
			}
		case VCall("cubic-bezier",[a,b,c,d]):
			inline function getVal(v) {
				return switch( v ) {
				case VFloat(f): f;
				case VInt(i): i;
				default: warn("Invalid value"); 0;
				}
			}
			curve = new BezierCurve(getVal(a), getVal(b), getVal(c), getVal(d));
		default:
			warn("Unknown easing curve "+valueStr(args[2]));
		}
		if( args.length > 3 )
			warn("Invalid argument "+valueStr(args[3]));
		return { p : p, time : time, curve : curve };
	}

	function parseStyle( eof ) {
		var rules = [], trans = null;
		while( true ) {
			if( isToken(eof) )
				break;
			var name = readIdent();
			var start = tokenStart;
			expect(TDblDot);
			var value = readValue();
			var p = Property.get(name, false);
			if( p == null ) {
				if( name == "transition" ) {
					if( trans == null ) trans = [];
					var values = switch( value ) {
					case VList(vl): vl;
					default: [value];
					}
					for( value in values ) {
						var t = parseTransition(value, start, pos);
						if( t != null ) trans.push(t);
					}
				} else
					warnings.push({ pmin : start, pmax : pos, msg : "Unknown property "+name });
			} else
				rules.push({ p : p, value : value, pmin : start, vmin : valueStart, pmax : pos });
			if( isToken(eof) )
				break;
			expect(TSemicolon);
		}
		return { rules : rules, transitions : trans };
	}

	public function parseSheet( css : String ) : CssSheet {
		this.css = css;
		pos = 0;
		tokens = [];
		warnings = [];
		warnedComponents = new Map();
		var rules : CssSheet = [];
		while( true ) {
			if( isToken(TEof) )
				break;
			var classes = readClasses();
			expect(TBrOpen);
			var style = parseStyle(TBrClose);
			rules.push({ classes : classes, style : style.rules, transitions: style.transitions });
			// removed unused components rules
			for( c in classes.copy() )
				if( c.className == "@" ) {
					classes.remove(c);
					if( classes.length == 0 )
						rules.pop();
				}
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
				case TSuperior:
					if( def ) {
						push(t);
						return readClass(c);
					}
					if( c.relation != None ) unexpected(t);
					c.relation = ImmediateChildren;
					t = readToken();
					if( t != TSpaces ) push(t);
				case TIdent(i):
					#if macro
					var comp = @:privateAccess Macros.loadComponent(i,p,this.pos);
					#else
					var comp = Component.get(i,true);
					#end
					if( comp == null ) {
						if( !warnedComponents.exists(i) ) {
							warnedComponents.set(i, true);
							warnings.push({ pmin : p, pmax : pos, msg : "Unknown component "+i });
						}
						c.className = "@"; // prevent it to be applied
					} else
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
					case TDot:
						if( c.className == null )
							c.className = i;
						else {
							if( c.extraClasses == null ) c.extraClasses = [];
							c.extraClasses.push(i);
						}
						def = true;
					case TSharp:
						c.id = i;
						def = true;
					case TDblDot:
						switch( i ) {
						case "hover":
							c.pseudoClasses |= HOver;
						case "disabled":
							c.pseudoClasses |= Disabled;
						case "first-child":
							c.pseudoClasses |= FirstChild;
							c.pseudoClasses |= NeedChildren;
						case "last-child":
							c.pseudoClasses |= LastChild;
							c.pseudoClasses |= NeedChildren;
						case "odd":
							c.pseudoClasses |= Odd;
							c.pseudoClasses |= NeedChildren;
						case "even":
							c.pseudoClasses |= Even;
							c.pseudoClasses |= NeedChildren;
						case "active":
							c.pseudoClasses |= Active;
						default:
							throw new Error("Unknown selector "+i, pos - i.length - 1, pos);
						}
						def = true;
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
					var v = readValue(true);
					var args = switch( v ) {
					case null: [];
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
			case ">".code: return TSuperior;
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

	/**
	 * Convert from haxe identifier haxeCasing to css haxe-casing
	 */
	public static function haxeToCss( name : String ) {
		// if fully uppercase, keep it this way
		if( name.toUpperCase() == name )
			return name.toLowerCase().split("_").join("-");

		var out = new StringBuf();
		for( i in 0...name.length ) {
			var c = name.charCodeAt(i);
			if( c >= "A".code && c <= "Z".code ) {
				if( i > 0 ) out.addChar("-".code);
				out.addChar(c - "A".code + "a".code);
			} else if( c == "_".code )
				out.addChar("-".code);
			else
				out.addChar(c);
		}
		return out.toString();
	}

}
