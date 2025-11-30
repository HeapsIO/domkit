package domkit;

import domkit.MarkupParser;
import hscript.Checker.TType in Type;
import hscript.Expr in Expr;

enum PropParser {
	PUnknown;
	PNamed( name : String );
	POpt( t : PropParser, def : String );
	PEnum( e : hscript.Checker.CEnum );
}

typedef TypedProperty = {
	var type : Type;
	var comp : TypedComponent;
	var field : String;
	var parser : PropParser;
}

typedef TypedComponent = {
	var name : String;
	var ?classDef : hscript.Checker.CClass;
	var ?parent : { comp : TypedComponent, params : Array<Type> };
	var properties : Map<String, TypedProperty>;
	var arguments : Array<{ name : String, t : Type, ?opt : Bool }>;
	var domkitComp : domkit.Component<Dynamic,Dynamic>;
}

class Checker extends hscript.Checker {

	public static var inst(get,default) : Checker;

	static function get_inst() {
		if( inst == null ) throw "Checker has not been initialized with domkit.Checker.init()";
		return inst;
	}

	public static function isInit() {
		return @:bypassAccessor inst != null;
	}

	public static function init( apiFile : String ) {
		inst = new Checker(apiFile);
	}

	public var t_string : Type;
	public var components : Map<String,TypedComponent>;
	public var properties : Map<String, Array<TypedProperty>>;
	var onMarkup : String -> Expr -> Void;

	public function new(apiFile:String) {
		var types = new hscript.Checker.CheckerTypes();
		var xml = Xml.parse(sys.io.File.getContent(apiFile));
		types.addXmlApi(xml.firstElement());
		super(types);
		initComponents();
		t_string = types.t_string;
		if( t_string == null )
			throw "Could not load API XML";
	}

	public function begin( onMarkup ) {
		this.onMarkup = onMarkup;
		check(#if hscriptPos { e : EBlock([]), pmin : 0, pmax : 0, origin : "", line : 0 } #else EBlock([]) #end);
	}

	public function done() {
		onMarkup = null;
	}

	public function haxeToCss( name : String ) {
		return CssParser.haxeToCss(name);
	}

	override function checkMeta(m:String, args:Array<Expr>, next:Expr, expr:Expr, withType):Type {
		if( m == ":markup" ) {
			switch( hscript.Tools.expr(next) ) {
			case EConst(CString(data)):
				onMarkup(data,next);
				return TVoid;
			default:
			}
		}
		return super.checkMeta(m, args, next, expr, withType);
	}

	override function getTypeAccess(t, expr, ?field) {
		var path = switch( t ) {
		case TInst(c,_): c.name;
		case TEnum(e,_): e.name;
		default: return null;
		}
		var e : hscript.Expr.ExprDef = ECall(mk(EIdent("__resolve"),expr),[mk(EConst(CString(path)),expr)]);
		if( field != null ) e = EField(mk(e,expr),field);
		return e;
	}

	public function resolveProperty( comp : TypedComponent, name : String ) {
		while( comp != null ) {
			var p = comp.properties.get(name);
			if( p != null )
				return p;
			comp = comp.parent?.comp;
		}
		return null;
	}

	function makeComponent(name) {
		var c : TypedComponent = {
			name : name,
			properties : [],
			arguments : [],
			domkitComp : domkit.Component.get(name, true),
		};
		if( c.domkitComp == null ) {
			c.domkitComp = std.Type.createEmptyInstance(domkit.Component);
			c.domkitComp.name = name;
		}
		components.set(name, c);
		return c;
	}

	function makePropParser( t : Type ) {
		return switch( t ) {
		case TInt: PNamed("Int");
		case TFloat: PNamed("Float");
		case TBool: PNamed("Bool");
		case TNull(t):
			POpt(makePropParser(t),"none");
		case TInst(c,_):
			switch( c.name ) {
			case "String": PNamed("String");
			default: PUnknown;
			}
		case TEnum(e,_):
			PEnum(e);
		default:
			var t2 = followOnce(t);
			if( t != t2 )
				makePropParser(t);
			else
				PUnknown;
		}
	}

	function initComponents() {
		components = [];
		properties = [];
		var cdefs = [];
		var cmap = new Map();
		for( t in types.types ) {
			var c = switch( t ) {
			case CTClass(c) if( c.meta != null ): c;
			default: continue;
			}
			var name = null;
			for( m in c.meta ) {
				if( m.name == ":build" && m.params.length > 0 ) {
					var str = hscript.Printer.toString(m.params[0]);
					if( str == "h2d.domkit.InitComponents.build()" ) {
						for( f in c.statics ) {
							if( f.name == "ref" ) {
								switch( f.t ) {
								case TInst(c,_) if( StringTools.startsWith(c.name,"domkit.Comp") ):
									name = haxeToCss(c.name.substr(11));
									break;
								default:
								}
							}
						}
						break;
					}
				}
			}
			if( name == null )
				continue;
			var comp = makeComponent(name);
			var cl = c;
			for( i in c.interfaces )
				switch( i ) {
				case TInst({ name : "domkit.ComponentDecl"},[TInst(creal,_)]):
					cmap.set(cl.name, comp);
					cl = creal;
				default:
				}
			comp.classDef = cl;
			cmap.set(cl.name, comp);
			if( c.constructor != null ) {
				switch( c.constructor.t ) {
				case TFun(args,_): comp.arguments = args;
				default:
				}
			}
			for( f in c.fields ) {
				var prop = null;
				if( f.meta != null ) {
					for( m in f.meta )
						if( m.name == ":p" ) {
							prop = m;
							break;
						}
				}
				if( prop != null ) {
					var p0 = prop.params.length == 0  ? null : hscript.Tools.expr(prop.params[0]);
					var parser = switch( p0 ) {
					case null: null;
					case EIdent(def = "auto"|"none"):
						switch( makePropParser(f.t) ) {
						case POpt(p,_), p: POpt(p,def);
						}
					case EIdent(name): PNamed(name.charAt(0).toUpperCase()+name.substr(1));
					default: null;
					};
					if( parser == null )
						parser = makePropParser(f.t);
					var name = haxeToCss(f.name);
					var p : TypedProperty = { field : f.name, type : f.t, parser : parser, comp : comp };
					comp.properties.set(name, p);
					var pl = properties.get(name);
					if( pl == null ) {
						pl = [];
						properties.set(name, pl);
						domkit.Property.get(name); // force create, prevent warning if used in css
					}
					var dup = false;
					for( p2 in pl )
						if( p2.parser.equals(p.parser) && p2.type.equals(p.type) ) {
							dup = true;
							break;
						}
					if( !dup )
						pl.push(p);
				}
			}
			cdefs.push({ name : name, c : c });
		}
		for( def in cdefs ) {
			var comp = components.get(def.name);
			var c = def.c;
			var p = c;
			var parent = null;
			var params = null;
			while( parent == null && p.superClass != null ) {
				switch( p.superClass ) {
				case null:
					break;
				case TInst(pp, pl):
					parent = cmap.get(pp.name);
					p = pp;
					if( params == null )
						params = pl;
					else
						params = [for( p in params ) apply(p, pp.params, pl)];
				default:
					throw "assert";
				}
			}
			if( parent != null )
				comp.parent = { comp : parent, params : params };
		}
	}

}

class DMLChecker {

	var filePath : String;
	var parser : hscript.Parser;
	var checker : Checker;
	public var parsers : Array<domkit.CssValue.ValueParser> = [new domkit.CssValue.ValueParser()];
	public var definedIdents : Map<String, Array<TypedComponent>> = new Map();

	public function new() {
		checker = Checker.inst;
	}

	public function parse( data : String, filePath : String, filePos : Int, locals : {} ) : Markup {
		var parser = new MarkupParser();
		var dml = parser.parse(data,filePath,filePos).children[0];
		this.filePath = filePath;
		this.parser = new hscript.Parser();
		checker.begin(parseMarkup);
		var pos = #if hscriptPos { e : null, pmin : dml.pmin, pmax : dml.pmax, line : 0, origin : filePath } #else null #end;
		for( l in Reflect.fields(locals) ) {
			var lval : Dynamic = Reflect.field(locals,l);
			@:privateAccess checker.locals.set(l, lval.type == null ? TUnresolved("Local#"+l) : checker.makeType(lval.type,pos));
		}
		switch( dml.kind ) {
		case Node(name):
			var c = checker.components.get(name);
			if( c != null ) @:privateAccess checker.locals.set("this", TInst(c.classDef,[]));
		default:
		}
		checkRec(dml, true);
		this.parser = null;
		checker.done();
		return dml;
	}

	function parseMarkup( data : String, expr : Expr ) {
		var parser = new MarkupParser();
		var dml = parser.parse(data,filePath,#if hscriptPos expr.pmin #else 0 #end).children[0];
		(expr:Dynamic).dml = dml;
		checkRec(dml);
	}

	function typeCode( code : String, pos : { pmin : Int, pmax : Int }, ?with : Type ) : Type {
		var expr = parser.parseString(code, filePath, pos.pmin);
		var t = @:privateAccess checker.typeExpr(expr, with == null ? Value : WithType(with));
		(pos:Dynamic).__expr = expr;
		return t;
	}

	function unify( t1 : Type, t2 : Type, comp : TypedComponent, prop : String, pos : { pmin : Int, pmax : Int } ) {
		if( !checker.tryUnify(t1, t2) ) {
			var e : Expr = (pos:Dynamic).__expr;
			if( e != null && checker.abstractCast(t1,t2,e) )
				return;
			throw new domkit.Error(typeStr(t1)+" should be "+typeStr(t2)+" for "+comp.name+"."+prop, pos.pmin, pos.pmax);
		}
	}

	function typeStr( t : Type ) {
		return hscript.Checker.typeStr(t);
	}

	inline function error( msg : String, pos : { pmin : Int, pmax : Int } ) {
		throw new Error(msg,pos.pmin,pos.pmax);
	}

	static var R_IDENT = ~/^([A-Za-z_-][A-Za-z0-9_-]*)$/;

	function checkRec( m : Markup, isRoot = false ) {
		switch( m.kind ) {
		case Node(name):
			var c = checker.components.get(name);
			if( c == null )
				error("Unknown component "+name,m);
			if( isRoot ) {
				if( m.arguments.length > 0 )
					error("Invalid arguments", m.arguments[0]);
			} else {
				for( i => a in m.arguments ) {
					var arg = c.arguments[i];
					if( arg == null )
						error("Too many arguments (require "+[for( a in c.arguments ) a.name].join(",")+")",a);
					var t = switch( a.value ) {
					case RawValue(_): checker.t_string;
					case Code(code): typeCode(code, a, arg.t);
					};
					unify(t, arg.t, c, arg.name, a);
				}
				for( i in m.arguments.length...c.arguments.length )
					if( !c.arguments[i].opt )
						error("Missing required argument "+c.arguments[i].name,m);
			}

			for( a in m.attributes ) {
				switch( a.name ) {
				case "public":
					continue;
				case "class":
					switch( a.value ) {
					case RawValue(str):
						for( cl in ~/[ \t]+/g.split(str) )
							defineIdent(c,cl);
					case Code(code):
						var t = try typeCode(code, a, checker.t_string) catch( e : hscript.Expr.Error ) typeCode("{"+code+"}",a);
						var texp = switch( t ) { case TAnon(fl): TAnon([for( f in fl ) { name : f.name, t : TBool, opt : false }]); default: checker.t_string; };
						unify(t, texp, c, "class", a);
						// TODO : define idents
					}
					continue;
				case "id":
					switch( a.value ) {
					case RawValue("true"):
						for( a in m.attributes )
							if( a.name == "class" ) {
								switch( a.value ) {
								case RawValue(str):
									var id = str.split(" ")[0];
									if( R_IDENT.match(id) ) {
										defineIdent(c, "#"+id);
										break;
									}
								default:
								}
								error("Auto-id reference invalid class",a);
								break;
							}
					case RawValue(id):
						defineIdent(c, "#"+id);
					case Code(_):
						error("Not constant id is not allowed",a);
					}
					continue;
				case "__content__":
					switch( a.value ) {
					case RawValue("true"):
						continue;
					default:
					}
				default:
				}
				var pname = checker.haxeToCss(a.name);
				var p = checker.resolveProperty(c, pname);
				if( p == null ) {
					var t = @:privateAccess checker.getField(TInst(c.classDef,c.classDef.params),a.name,{pmin:a.pmin,pmax:a.pmax,origin:filePath,line:1,e:null},true);
					if( t == null )
						error(c.name+" does not have property "+a.name, a);
					var pt = switch( a.value ) {
					case RawValue(_): checker.t_string;
					case Code(code): typeCode(code, a, t);
					}
					unify(pt, t, c, a.name, a);
					continue;
				}
				switch( a.value ) {
				case RawValue(str):
					typeProperty(pname, a.vmin, a.pmax, new domkit.CssParser().parseValue(str), c);
				case Code(code):
					var t = typeCode(code, a, p.type);
					unify(t, p.type, c, pname, a);
				}
			}
			if( m.condition != null ) {
				var cond = m.condition;
			 	var t = typeCode(cond.cond, cond, TBool);
				unify(t, TBool, c, "if", cond);
			}
			for( c in m.children )
				checkRec(c);
		case CodeBlock(v):
			typeCode(v, m);
		case For(cond):
			var expr = parser.parseString("for"+cond+"{}", filePath, m.pmin - 3);
			var prevLocals = @:privateAccess checker.locals.copy();
			@:privateAccess switch( hscript.Tools.expr(expr) ) {
			case EFor(v, it, _):
				var et = checker.getIteratorType(checker.typeExpr(it,Value),it);
				checker.locals.set(v, et);
			case EForGen(it,_):
				hscript.Tools.getKeyIterator(it, function(vk,vv,it) {
					if( vk == null ) {
						error("Invalid for loop", m);
						return;
					}
					var types = checker.getKeyIteratorTypes(checker.typeExpr(it,Value),it);
					checker.locals.set(vk, types.key);
					checker.locals.set(vv, types.value);
				});
			default:
				error("Invalid for loop", m);
			}
			for( c in m.children )
				checkRec(c);
			@:privateAccess checker.locals = prevLocals;
			(m:Dynamic).__expr = expr;
		case Text(_), Macro(_):
		}
	}

	function typeProperty( pname : String, pmin : Int, pmax : Int, value : domkit.CssValue, ?comp : TypedComponent ) {
		inline function error(msg) {
			throw new domkit.Error(msg, pmin, pmax);
		}
		var pl = [];
		if( comp != null ) {
			var p = checker.resolveProperty(comp, pname);
			if( p == null )
				error(comp.name+" does not have property "+pname);
			pl = [p];
		} else {
			pl = checker.properties.get(pname);
			if( pl == null )
				error("Unknown property "+pname);
		}
		var err : String = null;
		for( p in pl ) {
			var msg = checkParser(p, p.parser, value);
			if( msg == null ) return;
			if( err == null || err.length < msg.length )
				err = msg;
		}
		error(err);
	}

	function haxeToCss( name : String ) {
		return name.charAt(0).toLowerCase()+~/[A-Z]/g.map(name.substr(1), (r) -> "-"+r.matched(0).toLowerCase());
	}

	function checkParser( p : TypedProperty, parser : PropParser, value : domkit.CssValue ) {
		switch( parser ) {
		case PUnknown:
			// no check
			return null;
		case PNamed(name):
			var err : String = null;
			for( parser in parsers ) {
				var f = Reflect.field(parser, "parse"+name);
				if( f != null ) {
					try {
						Reflect.callMethod(parser, f, [value]);
						return null;
					} catch( e : domkit.Property.InvalidProperty ) {
						if( err == null || (e.message != null && e.message.length < err.length) )
							err = e.message ?? "Invalid property "+domkit.CssParser.valueStr(value)+" (should be "+name+")";
					}
				}
			}
			return err ?? "Could not find matching parser";
		case POpt(t, def):
			switch( value ) {
			case VIdent(n) if( n == def ):
				return null;
			default:
				return checkParser(p, t, value);
			}
		case PEnum(e):
			switch( value ) {
			case VIdent(i):
				for( c in e.constructors ) {
					if( (c.args == null || c.args.length == 0) && haxeToCss(c.name) == i )
						return null;
				}
			default:
			}
			return domkit.CssParser.valueStr(value)+" should be "+[for( c in e.constructors ) if( c.args == null || c.args.length == 0 ) haxeToCss(c.name)].join("|");
		}
	}

	public function defineIdent( c : TypedComponent, cl : String ) {
		var comps = definedIdents.get(cl);
		if( comps == null ) {
			comps = [];
			definedIdents.set(cl, comps);
		}
		if( comps.indexOf(c) < 0 )
			comps.push(c);
	}

	public function checkCSS( rules : CssParser.CssSheet ) {
		for( r in rules ) {
			var comp = { r : null };
			inline function setComp(c:TypedComponent) {
				if( comp.r == null || comp.r == c )
					comp.r = c;
				else
					comp = null;
			}
			for( c in r.classes ) {
				if( c.component == null ) {
					if( c.id != null ) {
						var comps = definedIdents.get("#"+c.id.toString());
						if( comps == null || comps.length > 1 )
							comp = null;
						else
							setComp(comps[0]);
					} else
						comp = null;
				} else {
					var comp = checker.components.get(c.component.name);
					setComp(comp);
				}
				if( comp == null ) break;
			}
			for( s in r.style ) {
				var value = s.value;
				switch( s.value ) {
				case VLabel("important", val): value = val;
				default:
				}
				typeProperty(s.p.name, s.pmin, s.pmax, value, comp?.r);
			}
		}
	}

}