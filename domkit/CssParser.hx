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
	TPlus;
	TMinus;
	TBkOpen;
	TBkClose;
	TSuperior;
	TAnd;
	TAt;
}

enum abstract PseudoClass(Int) {

	var None = 0;
	var Hover = 1;
	var FirstChild = 2;
	var LastChild = 4;
	var Odd = 8;
	var Even = 16;
	var Active = 32;
	var Disabled = 64;
	var Focus = 128;
	var NotImportant = 256;

	// set for some flags requiring children checks
	var NeedChildren = 512;

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
	var SubRule = 2;
}

class CssClass {
	public var parent : Null<CssClass>;
	public var component : Null<Component<Dynamic,Dynamic>>;
	public var id : Identifier;
	public var className : Null<Identifier>;
	public var extraClasses : Null<Array<Identifier>>;
	public var pseudoClasses : PseudoClass = None;
	public var relation : CssRelation = None;
	public function new() {
	}
	public function withParent(cl:CssClass) {
		var c = new CssClass();
		if( relation == SubRule ) {
			if( parent != null ) throw "assert";
			c.parent = cl.parent;
			c.component = component ?? cl.component;
			c.id = id.isDefined() ? id : cl.id;
			c.className = className ?? cl.className;
			if( className != null && cl.className != null ) {
				c.extraClasses = [cl.className];
				if( extraClasses != null ) {
					for( cl in extraClasses )
						c.extraClasses.push(cl);
				}
				if( cl.extraClasses != null ) {
					for( cl in cl.extraClasses )
						c.extraClasses.push(cl);
				}
			} else {
				c.extraClasses = extraClasses ?? cl.extraClasses;
			}
			c.pseudoClasses = pseudoClasses | cl.pseudoClasses;
			c.relation = cl.relation;
		} else {
			c.parent = parent == null ? cl : parent.withParent(cl);
			c.component = component;
			c.id = id;
			c.className = className;
			c.extraClasses = extraClasses;
			c.pseudoClasses = pseudoClasses;
			c.relation = relation;
		}
		return c;
	}

	public function toString() {
		var str = [];
		if( parent != null )
			str.push(parent.toString());
		switch( relation ) {
		case None: if( str.length > 0 ) str.push(" ");
		case ImmediateChildren: str.push(">");
		case SubRule: str.push("&");
		}
		if( component != null )
			str.push(component.name);
		if( className != null )
			str.push("."+className.toString());
		if( extraClasses != null )
			for( e in extraClasses )
				str.push("."+e.toString());
		if( id.isDefined() )
			str.push("#"+id.toString());
		if( pseudoClasses != None ) {
			var ps = pseudoClasses;
			if( ps.has(Hover) ) str.push(":hover");
			if( ps.has(FirstChild) ) str.push(":first-child");
			if( ps.has(LastChild) ) str.push(":last-child");
			if( ps.has(Odd) ) str.push(":odd");
			if( ps.has(Even) ) str.push(":even");
			if( ps.has(Active) ) str.push(":active");
			if( ps.has(Disabled) ) str.push(":disabled");
			if( ps.has(Focus) ) str.push(":focus");
			if( ps.has(NotImportant) ) str.push(":not-important");
		}
		return str.join("");
	}

}

typedef Transition = {
	var p : Property;
	var time : Float;
	var curve : Curve;
}

typedef CssSheet = Array<CssSheetElement>;

typedef CssRule = { p : Property, value : CssValue, pmin : Int, vmin : Int, pmax : Int, file: String };

typedef CssSheetElement = {
	var classes : Array<CssClass>;
	var style : Array<CssRule>;
	var ?transitions : Array<Transition>;
	var ?subRules : CssSheet;
 }


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
	var calc : Int;
	var file: String;
	var tokenStart : Int;
	var valueStart : Int;
	var lazyVars : Bool;
	var spacesTokens : Bool;
	var tokens : Array<Token>;
	var warnedComponents : Map<String,Bool>;
	public var warnings : Array<{ pmin : Int, pmax : Int, msg : String }>;
	public var allowSubRules = true;
	public var allowVariablesDecl = true;
	public var allowMixins = true;
	public var expandSubRules = true;
	public var allowSingleLineComment = true;
	public var variables : Map<String, CssValue> = [];
	public var mixins : Map<String, { rules : CssSheetElement, args : Array<String> }> = [];

	static var ERASED = new Identifier("@");
	static var DEFAULT_CURVE : Curve = new BezierCurve(0.25,0.1,0.25,1.0);
	static var CURVES : Map<String,Curve> = [
		"ease" => DEFAULT_CURVE,
		"linear" => new Curve(),
		"ease-in" => new BezierCurve(0.42, 0, 1.0, 1.0),
		"ease-out" => new BezierCurve(0, 0, 0.58, 1.0),
		"ease-in-out" => new BezierCurve(0.42, 0, 0.58, 1.0),
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
			case TSemicolon: ";";
			case TBrOpen: "{";
			case TBrClose: "}";
			case TDot: ".";
			case TSpaces: "space";
			case TSlash: "/";
			case TStar: "*";
			case TPlus: "+";
			case TMinus: "-";
			case TBkOpen: "[";
			case TBkClose: "]";
			case TSuperior: ">";
			case TAnd: "&";
			case TAt: "@";
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

	function reset() {
		pos = 0;
		calc = 0;
		tokens = [];
		warnings = [];
		lazyVars = false;
		spacesTokens = false;
	}

	public function parse( css : String, ?file : String ) {
		this.css = css;
		reset();
		this.file = file;
		return parseStyle(null, TEof);
	}

	public function parseValue( valueStr : String ) {
		this.css = valueStr;
		reset();
		if( isToken(TEof) )
			return VString("");
		var v = readValue();
		expect(TEof);
		return v;
	}

	public static function opStr(op:CssOp) {
		return switch( op ) {
		case OAdd:"+";
		case OSub:"-";
		case OMult:"*";
		case ODiv:"/";
		}
	}

	public static function valueMap( v : CssValue, f : CssValue -> CssValue ) {
		return switch( v ) {
		case VIdent(_), VString(_), VUnit(_), VFloat(_), VInt(_), VHex(_), VSlash: v;
		case VList(vl): VList([for( v in vl ) f(v)]);
		case VGroup(vl): VGroup([for( v in vl ) f(v)]);
		case VCall(a,vl): VCall(a,[for( v in vl ) f(v)]);
		case VLabel(l,v): VLabel(l,f(v));
		case VArray(v, content): VArray(f(v), content == null ? null : f(content));
		case VOp(op,v1,v2): VOp(op,f(v1),f(v2));
		case VParent(v): VParent(f(v));
		case VVar(v): VVar(v);
		}
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
		case VOp(op,v1,v2): valueStr(v1)+opStr(op)+valueStr(v2);
		case VParent(v): "("+valueStr(v)+")";
		case VVar(v): "@"+v;
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

	function parseStyle( classes, eof ) : CssSheetElement {
		var elt : CssSheetElement = { classes : classes, style : [] };
		var oldVars = null;
		while( true ) {
			if( isToken(eof) )
				break;
			var tk = readToken();
			var name = switch( tk ) {
			case TAt if( allowVariablesDecl ):
				var name = readIdent();
				expect(TDblDot);
				var value = readValue();
				expect(TSemicolon);
				if( oldVars == null ) oldVars = variables.copy();
				variables.set(name, value);
				continue;
			case TIdent(n): n;
			case TAnd, TSuperior, TSharp, TDot, TDblDot if( allowSubRules ):
				push(tk);
				if( elt.subRules == null ) elt.subRules = [];
				for( e in parseSheetElements(elt) )
					elt.subRules.push(e);
				continue;
			default:
				unexpected(tk);
			}
			var hasSpaces = false;
			var isSubRule = false;
			var start = 0;
			while( true ) {
				spacesTokens = true;
				start = tokenStart;
				var tk = readToken();
				spacesTokens = false;
				switch( tk ) {
				case TDblDot:
					// subrule in the form `name:pseudo {`
					if( allowSubRules && !hasSpaces ) {
						spacesTokens = true;
						var tk2 = readToken();
						spacesTokens = false;
						switch( tk2 ) {
						case TIdent(pseudo):
							var tk3 = readToken();
							push(tk3);
							push(tk2);
							if( tk3 != TBrOpen )
								break;
							push(tk);
							isSubRule = true;
						default:
							if( tk2 != TSpaces ) push(tk2);
							break;
						}
					}
					break;
				case TSpaces:
					hasSpaces = true;
				case tk if( allowSubRules ):
					push(tk);
					isSubRule = true;
					break;
				case tk:
					push(tk);
					expect(TDblDot);
				}
			}
			if( isSubRule ) {
				if( hasSpaces ) push(TSpaces);
				push(TIdent(name));
				if( elt.subRules == null ) elt.subRules = [];
				for( e in parseSheetElements(elt) )
					elt.subRules.push(e);
				continue;
			}
			var value = readValue();
			var p = Property.get(name, false);
			if( p == null ) {
				if( name == "transition" ) {
					if( elt.transitions == null ) elt.transitions = [];
					var values = switch( value ) {
					case VList(vl): vl;
					default: [value];
					}
					for( value in values ) {
						var t = parseTransition(value, start, pos);
						if( t != null ) elt.transitions.push(t);
					}
				} else
					warnings.push({ pmin : start, pmax : pos, msg : "Unknown property "+name });
			} else
				elt.style.push({ p : p, value : value, pmin : start, vmin : valueStart, pmax : pos, file: file });
			if( isToken(eof) )
				break;
			expect(TSemicolon);
		}
		if( oldVars != null ) variables = oldVars;
		return elt;
	}

	public function parseSheet( css : String, ?file : String ) : CssSheet {
		this.css = css;
		reset();
		this.file = file;
		tokens = [];
		warnings = [];
		warnedComponents = new Map();
		var rules : CssSheet = [];
		while( true ) {
			if( isToken(TEof) )
				break;
			if( allowVariablesDecl && isToken(TAt) ) {
				var name = readIdent();
				expect(TDblDot);
				var value = readValue();
				expect(TSemicolon);
				variables.set(name, value);
				continue;
			}
			for( e in parseSheetElements(null) )
				rules.push(e);
		}
		return rules;
	}

	function getFunIdent( c : CssClass ) {
		if( c.parent != null )
			return null;
		if( c.component != null )
			return null;
		if( c.extraClasses != null )
			return null;
		if( c.pseudoClasses.toInt() != 0 )
			return null;
		if( c.id.isDefined() )
			return null;
		if( !c.className.isDefined() )
			return null;
		if( c.relation != None )
			return null;
		return c.className.toString();
	}

	function evalRule( r : CssRule ) : CssRule {
		return { file : r.file, p : r.p, pmin : r.pmin, pmax : r.pmax, vmin : r.vmin, value : evalRec(r.value) };
	}

	function evalSubRule( r : CssSheetElement ) : CssSheetElement {
		return {
			classes : r.classes,
			style : [for( s in r.style ) evalRule(s)],
			transitions : r.transitions,
			subRules : r.subRules == null ? null : [for( s in r.subRules ) evalSubRule(s)],
		};
	}

	function parseSheetElements(parent:CssSheetElement) : Array<CssSheetElement> {
		var pmin = tokenStart;
		var classes = readClasses(parent != null);
		if( allowMixins && classes.length == 1 && getFunIdent(classes[0]) != null && isToken(TPOpen) ) {
			var name = getFunIdent(classes[0]);
			var args = [];
			lazyVars = true;
			calc++;
			var arg = readValue(true);
			calc--;
			lazyVars = false;
			if( arg != null ) {
				switch( arg ) {
				case VList(vl): args = vl;
				default: args = [arg];
				}
			}
			expect(TPClose);
			if( isToken(TBrOpen) ) {
				var args = [for( a in args ) switch( a ) {
				case VVar(name): name;
				default: error("Unknown mixin ."+name+"()"); null;
				}];
				var prevVars = null;
				if( args.length > 0 ) {
					prevVars = variables.copy();
					for( a in args )
						variables.set(a, VVar(a));
				}
				calc++;
				var rules = parseStyle([null], TBrClose);
				calc--;
				mixins.set(name, { args : args, rules : rules });
				if( prevVars != null ) variables = prevVars;
				return [];
			} else {
				expect(TSemicolon);
				var fun = mixins.get(name);
				if( fun == null )
					error("Unknown mixin ."+name+"()");
				else if( args.length < fun.args.length )
					error("Missing mixins params : ("+fun.args.join(",")+") required");
				else if( args.length > fun.args.length )
					error("Too many mixins params : ("+fun.args.join(",")+") required");
				var prevVars = null;
				var hasArg = args.length > 0;
				if( args.length > 0 ) {
					prevVars = variables.copy();
					for( i => a in args )
						variables.set(fun.args[i], a);
				}
				for( r in fun.rules.style )
					parent.style.push(hasArg ? evalRule(r) : r);
				if( fun.rules.transitions != null ) {
					if( parent.transitions == null ) parent.transitions = [];
					for( t in fun.rules.transitions )
						parent.transitions.push(t);
				}
				if( fun.rules.subRules != null ) {
					if( parent.subRules == null ) parent.subRules = [];
					for( r in fun.rules.subRules )
						parent.subRules.push(hasArg ? evalSubRule(r) : r);
				}
				if( hasArg ) variables = prevVars;
				return [];
			}
		}
		expect(TBrOpen);
		var elt = parseStyle(classes, TBrClose);
		// removed unused components rules
		for( c in classes.copy() )
			if( c.className == ERASED ) {
				classes.remove(c);
				if( classes.length == 0 )
					return [];
			}
		if( expandSubRules && elt.subRules != null ) {
			var out = [];
			var subs = elt.subRules;
			if( elt.style.length > 0 || elt.transitions != null ) {
				elt.subRules = null;
				out.push(elt);
			}
			for( s in subs ) {
				for( pcl in elt.classes ) {
					var cl = [for( c in s.classes ) c.withParent(pcl)];
					out.push({ classes : cl, style : s.style, transitions : s.transitions, subRules : null });
				}
			}
			return out;
		}
		return [elt];
	}

	public function parseClasses( css : String, ?hasParent, ?file : String ) {
		this.css = css;
		this.file = file;
		reset();
		var c = readClasses(hasParent);
		expect(TEof);
		return c;
	}

	// ----------------- class parser ---------------------------

	function readClasses(hasParent) {
		var classes = [];
		while( true ) {
			spacesTokens = true;
			isToken(TSpaces); // skip
			var c = readClass(null, hasParent);
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

	function resolveComponent( i : String, p : Int ) {
		#if macro
		return @:privateAccess Macros.loadComponent(i,p,this.pos,true);
		#else
		return Component.get(i,true);
		#end
	}

	function readClass( parent, hasParent ) : CssClass {
		var c = new CssClass();
		c.parent = parent;
		var def = false;
		var last = null;
		var first = true;
		while( true ) {
			var p = pos;
			var t = readToken();
			if( hasParent && first ) {
				first = false;
				if( t == TAnd ) {
					c.relation = SubRule;
					t = readToken();
				}
				if( t == TSuperior ) {
					// &> and > are same thing
					c.relation = ImmediateChildren;
					t = readToken();
					if( t == TSpaces ) t = readToken();
				}
			}
			if( last == null )
				switch( t ) {
				case TStar: def = true;
				case TDot, TSharp, TDblDot: last = t;
				case TSuperior:
					if( def ) {
						push(t);
						return readClass(c, false);
					}
					if( c.relation != None ) unexpected(t);
					c.relation = ImmediateChildren;
					t = readToken();
					if( t != TSpaces ) push(t);
				case TIdent(i):
					var comp = resolveComponent(i, p);
					if( comp == null ) {
						if( !warnedComponents.exists(i) ) {
							warnedComponents.set(i, true);
							warnings.push({ pmin : p, pmax : pos, msg : "Unknown component "+i });
						}
						c.className = ERASED; // prevent it to be applied
					} else
						c.component = comp;
					def = true;
				case TSpaces:
					return def ? readClass(c, false) : null;
				case TBrOpen, TComma, TEof:
					push(t);
					break;
				case TPOpen if( allowMixins ):
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
							c.className = new Identifier(i);
						else {
							if( c.extraClasses == null ) c.extraClasses = [];
							c.extraClasses.push(new Identifier(i));
						}
						def = true;
					case TSharp:
						c.id = new Identifier(i);
						def = true;
					case TDblDot:
						switch( i ) {
						case "hover":
							c.pseudoClasses |= Hover;
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
						case "focus":
							c.pseudoClasses |= Focus;
						case "not-important":
							c.pseudoClasses |= NotImportant;
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
		case TAt:
			var name = readIdent();
			if( lazyVars )
				VVar(name);
			else {
				var value = variables.get(name);
				if( value == null )
					error("Unknown variable @"+name);
				value;
			}
		case TPOpen:
			calc++;
			var v = readValue();
			expect(TPClose);
			calc--;
			eval(VParent(v));
		case TMinus:
			calc++;
			var v = readValue();
			calc--;
			eval(makeOp(OSub,VInt(0),v));
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

	function eval( v : CssValue ) {
		if( calc > 0 ) return v;
		return evalRec(v);
	}

	function evalRec( v : CssValue ) {
		switch(v) {
		case VOp(op,v1,v2):
			v1 = evalRec(v1);
			v2 = evalRec(v2);
			function calc(a:Float,b:Float) {
				return switch( op ) {
				case OAdd: a + b;
				case OSub: a - b;
				case OMult: a * b;
				case ODiv: a / b;
				}
			}
			switch( [v1, v2] ) {
			case [VInt(i1),VInt(i2)]:
				return VInt(Std.int(calc(i1,i2)));
			case [VUnit(v1,u1), VUnit(v2,u2)] if( u1 == u2 ):
				return VUnit(calc(v1,v2),u1);
			case [VUnit(_), VUnit(_)]:
				// error
			default:
				function getFloat(v:CssValue) {
					return switch( v ) {
					case VInt(i): i;
					case VFloat(f): f;
					case VUnit(f,_): f;
					default: Math.NaN;
					}
				}
				var r = calc(getFloat(v1),getFloat(v2));
				if( !Math.isNaN(r) ) {
					return switch( [v1,v2] ) {
					case [VUnit(_,u), _] | [_,VUnit(_,u)]: VUnit(r,u);
					default: VFloat(r);
					}
				}
			}
			error("Cannot calc "+valueStr(v));
			return null;
		case VParent(v):
			return evalRec(v);
		case VVar(v):
			var val = variables.get(v);
			if( val == null ) error("Unbound variable @"+v);
			return val;
		default:
			return valueMap(v, evalRec);
		}
	}

	function makeOp( op : CssOp, v1 : CssValue, v2 : CssValue ) {
		switch( v2 ) {
		case VGroup(vl):
			var v3 = vl.shift();
			vl.unshift(makeOp(op,v1,v3));
			return v2;
		case VOp(op2,v2,v3) if( op2.getIndex() <= op.getIndex() ):
			return VOp(op2,makeOp(op,v1,v2),v3);
		default:
			return VOp(op, v1, v2);
		}
	}

	function readOp( op, v ) {
		calc++;
		var op = makeOp(op, v, readValue());
		calc--;
		return eval(op);
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
		case TStar:
			return readOp(OMult, v);
		case TPlus:
			return readOp(OAdd, v);
		case TMinus:
			return readOp(OSub, v);
		case TSlash:
			return readOp(ODiv, v);
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
				var spos = pos;
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
				if( pos == spos && neg )
					return TMinus;
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
			case "&".code: return TAnd;
			case "@".code: return TAt;
			case "-".code: return TMinus;
			case "+".code: return TPlus;
			case "/".code:
				var start = pos - 1;
				if( (c = next()) != '*'.code ) {
					if( c == "/".code && allowSingleLineComment ) {
						while( true ) {
							c = next();
							if( StringTools.isEof(c) || c == '\n'.code )
								break;
						}
						pos--;
						return readToken();
					}
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
				var buf : StringBuf = null;
				while( (k = next()) != c ) {
					if( StringTools.isEof(k) ) {
						this.pos = pos;
						error("Unclosed string constant");
					}
					if( k == "\\".code ) {
						if( buf == null ) {
							buf = new StringBuf();
							buf.add(css.substr(pos, this.pos - pos - 1));
						}
						k = next();
						if( StringTools.isEof(k) ) {
							this.pos = pos;
							error("Unclosed string constant");
						}
						switch( k ) {
						case 'n'.code: buf.addChar('\n'.code);
						case 't'.code: buf.addChar('\t'.code);
						case 'r'.code: buf.addChar('\r'.code);
						default: buf.addChar(k);
						}
						continue;
					}
					if( buf != null ) buf.addChar(k);
 				}
				return TString(buf != null ? buf.toString() : css.substr(pos, this.pos - pos - 1));
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

	public static function cssToHaxe( name : String, isField=false ) {
		var uname = name;
		if( !isField )
			uname = name.charAt(0).toUpperCase()+name.substr(1);
		var parts = uname.split("-");
		if( parts.length > 1 ) {
			for( i in 1...parts.length )
				parts[i] = parts[i].charAt(0).toUpperCase() + parts[i].substr(1);
			uname = parts.join("");
		}
		return uname;
	}

}
