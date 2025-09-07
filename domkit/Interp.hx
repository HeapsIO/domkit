package domkit;
import domkit.MarkupParser;
import hscript.Checker.TType in Type;
import hscript.Expr in Expr;

private enum PropParser {
	PUnknown;
	PNamed( name : String );
	POpt( t : PropParser, def : String );
	PEnum( e : hscript.Checker.CEnum );
}

private typedef TypedProperty = {
	var type : Type;
	var comp : TypedComponent;
	var field : String;
	var parser : PropParser;
}

private typedef TypedComponent = {
	var name : String;
	var ?classDef : hscript.Checker.CClass;
	var ?parent : { comp : TypedComponent, params : Array<Type> };
	var properties : Map<String, TypedProperty>;
	var vars : Map<String, Type>;
	var arguments : Array<{ name : String, t : Type, ?opt : Bool }>;
	var domkitComp : domkit.Component<Dynamic,Dynamic>;
}

class ScriptInterp extends hscript.Interp {

	var ctx : Interp;
	var obj : Model<Dynamic>;
	var objLocals : {};

	public function new(ctx,obj,locals) {
		super();
		this.ctx = ctx;
		this.obj = obj;
		this.objLocals = locals;
	}

	override function exprMeta(meta:String, args:Array<hscript.Expr>, e:hscript.Expr):Dynamic {
		if( meta == ":markup" ) {
			switch( hscript.Tools.expr(e) ) {
			case EConst(CString(data)):
				var dml = (e:Dynamic).dml;
				@:privateAccess ctx.buildRec(dml, ctx.currentObj);
				return null;
			default:
			}
		}
		return super.exprMeta(meta,args,e);
	}

	override function resolve( id : String ) : Dynamic {
		if( variables.exists(id) )
			return super.resolve(id);
		var v : Dynamic = Reflect.field(objLocals,id);
		if( v != null )
			return v.value;
		var v = Reflect.getProperty(obj, id);
		if( v != null )
			return v; // doesn't work for reading null obj field (fix with compilation)
		error(EUnknownVariable(id));
		return null;
	}

	public function executeLoop( n : String, it : hscript.Expr, callb ) {
		var old = declared.length;
		declared.push({ n : n, old : locals.get(n) });
		var it = makeIterator(expr(it));
		while( it.hasNext() ) {
			locals.set(n,{ r : it.next() });
			if( !loopRun(callb) )
				break;
		}
		restore(old);
	}

	public function executeKeyValueLoop( vk : String, vv : String, it : hscript.Expr, callb ) {
		var old = declared.length;
		declared.push({ n : vk, old : locals.get(vk) });
		declared.push({ n : vv, old : locals.get(vv) });
		var it = makeKeyValueIterator(expr(it));
		while( it.hasNext() ) {
			var v = it.next();
			locals.set(vk,{ r : v.key });
			locals.set(vv,{ r : v.value });
			if( !loopRun(callb) )
				break;
		}
		restore(old);
	}

}

class ScriptChecker extends hscript.Checker {

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

	public function init( onMarkup ) {
		this.onMarkup = onMarkup;
		check({ e : EBlock([]), pmin : 0, pmax : 0, origin : "", line : 0 });
	}

	public function done() {
		onMarkup = null;
	}

	public function haxeToCss( name : String ) {
		return name.charAt(0).toLowerCase()+~/[A-Z]/g.map(name.substr(1), (r) -> "-"+r.matched(0).toLowerCase());
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

	function makeComponent(name) {
		var c : TypedComponent = {
			name : name,
			properties : [],
			arguments : [],
			vars : [],
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
		return switch( follow(t) ) {
		case TInt: PNamed("Int");
		case TFloat: PNamed("Float");
		case TBool: PNamed("Bool");
		case TAbstract(a,params):
			return switch( a.name ) {
			case "Null": POpt(makePropParser(params[0]), "none"); // todo : auto?
			default: PUnknown;
			}
		case TInst(c,_):
			switch( c.name ) {
			case "String": PNamed("String");
			default: PUnknown;
			}
		case TEnum(e,_):
			PEnum(e);
		default:
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
			comp.classDef = c;
			cmap.set(c.name, comp);
			if( StringTools.startsWith(c.name,"h2d.domkit.") )
				cmap.set("h2d."+c.name.substr(11,c.name.length-11-4), comp);
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
					var parser = switch( prop.params[0] ) {
					case null: null;
					case { e : EIdent(def = "auto"|"none") }:
						switch( makePropParser(f.t) ) {
						case POpt(p,_), p: POpt(p,def);
						}
					case { e : EIdent(name) }: PNamed(name.charAt(0).toUpperCase()+name.substr(1));
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
				} else if( f.canWrite )
					comp.vars.set(f.name, f.t);
			}
			cdefs.push({ name : name, c : c });
		}
		for( def in cdefs ) {
			var comp = components.get(def.name);
			var c = def.c;
			var p = c;
			var parent = null;
			while( parent == null && p.superClass != null ) {
				switch( p.superClass ) {
				case null:
					break;
				case TInst(pp, pl):
					parent = { comp : cmap.get(pp.name), params : pl };
					p = pp;
				default:
					throw "assert";
				}
			}
			comp.parent = parent;
		}
	}

}

class Interp {

	public static var enable(default,set) : Bool = false;
	public static var SRC_PATHS = ["."];

	static function set_enable(b) {
		if( b && checker == null ) throw "Cannot enable before calling initChecker()";
		return enable = b;
	}

	public static var checker : ScriptChecker;
	public static function setChecker( apiFile : String ) {
		checker = new ScriptChecker(apiFile);
	}

	var compName : String;
	var fileName : String;
	var filePath : String;
	var dml : Markup;
	var root : Model<Dynamic>;
	var currentObj : Model<Dynamic>;
	var parser : hscript.Parser;
	var interp : ScriptInterp;
	var locals : {};

	function new( compName, fileName, locals ) {
		this.compName = compName;
		this.fileName = fileName;
		this.locals = locals;
		load();
	}

	function load() {
		for( dir in SRC_PATHS ) {
			var path = dir+"/"+fileName;
			if( sys.FileSystem.exists(path) ) {
				var compReg = ~/SRC[ \t\r\n]*=[ \t\r\n]*/;
				var content = sys.io.File.getContent(path);
				var current = content;
				while( compReg.match(current) ) {
					var next = compReg.matchedRight();
					if( StringTools.startsWith(next,"<"+compName) ) {
						var startPos = content.length - next.length;
						var endTag = "</"+compName+">";
						var endPos = next.indexOf(endTag);
						if( endPos < 0 ) throw 'Missing $endTag in $path';
						parse(next.substr(0,endPos+endTag.length), path, startPos);
						return;
					}
					current = next;
				}
				// NO SRC ? skip
				return;
			}
		}
		throw fileName+" was not found";
	}

	function parse( data : String, filePath : String, filePos : Int ) {
		var parser = new MarkupParser();
		dml = parser.parse(data,filePath,filePos).children[0];
		this.filePath = filePath;
		this.parser = new hscript.Parser();
		checker.init(parseMarkup);
		var pos = #if hscriptPos { e : null, pmin : dml.pmin, pmax : dml.pmax, line : 0, origin : filePath } #else null #end
		for( l in Reflect.fields(locals) ) {
			var lval : Dynamic = Reflect.field(locals,l);
			@:privateAccess checker.locals.set(l, checker.makeType(lval.type,pos));
		}

		checkRec(dml);
		this.parser = null;
		checker.done();
	}

	function parseMarkup( data : String, expr : Expr ) {
		var parser = new MarkupParser();
		var dml = parser.parse(data,filePath,#if hscriptPos expr.pmin #else 0 #end).children[0];
		(expr:Dynamic).dml = dml;
		checkRec(dml);
	}

	function typeCode( code : String, pos : { pmin : Int, pmax : Int }, ?with : Type ) : Type {
		var expr = parser.parseString(code, fileName, pos.pmin);
		var t = @:privateAccess checker.typeExpr(expr, with == null ? Value : WithType(with));
		(pos:Dynamic).__expr = expr;
		return t;
	}

	function unify( t1 : Type, t2 : Type, comp : TypedComponent, prop : String, pos : { pmin : Int, pmax : Int } ) {
		if( !checker.tryUnify(t1, t2) )
			throw new domkit.Error(typeStr(t1)+" should be "+typeStr(t2)+" for "+comp.name+"."+prop, pos.pmin, pos.pmax);
	}

	function typeStr( t : Type ) {
		return hscript.Checker.typeStr(t);
	}

	function checkRec( m : Markup ) {
		switch( m.kind ) {
		case Node(name):
			var c = checker.components.get(name);
			if( c == null )
				error("Unknown component "+name,m);
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

			for( a in m.attributes ) {
				var pname = checker.haxeToCss(a.name);
				switch( pname ) {
				case "class":
					switch( a.value ) {
					case RawValue(_):
						continue;
					case Code(code):
						var t = try typeCode(code, a, checker.t_string) catch( e : hscript.Expr.Error ) typeCode("{"+code+"}",a);
						var texp = switch( t ) { case TAnon(fl): TAnon([for( f in fl ) { name : f.name, t : TBool, opt : false }]); default: checker.t_string; };
						unify(t, texp, c, "class", a);
						continue;
					}
				case "id":
					switch( a.value ) {
					case RawValue(_):
						continue;
					case Code(_):
						error("Not constant id is not allowed",a);
					}
				case "__content__":
					switch( a.value ) {
					case RawValue("true"):
						continue;
					default:
					}
				default:
				}
				/*
				var p = resolveProperty(c, pname);
				if( p == null ) {
					var t = null, cur = c, chain = [];
					while( t == null && cur != null ) {
						t = cur.vars.get(a.name);
						if( t == null )
							chain.unshift(cur);
						cur = cur.parent?.comp;
					}
					if( t == null )
						domkitError(c.name+" does not have property "+a.name, a.pmin, a.pmax);
					for( c in chain )
						if( c.parent.params.length > 0 )
							t = checker.apply(t, c.parent.comp.classDef.params, c.parent.params);
					var pt = switch( a.value ) {
					case RawValue(_): t_string;
					case Code(code): typeCode(code, a.vmin, t);
					}
					unify(pt, t, c, a.name, a);
					continue;
				}
				switch( a.value ) {
				case RawValue(str):
					typeProperty(pname, a.vmin, a.pmax, new domkit.CssParser().parseValue(str), c);
				case Code(code):
					var t = typeCode(code, a.vmin, p.type);
					unify(t, p.type, c, pname, a);
				}
				*/
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
			typeCode("for"+cond+"{}",m);
			var expr : hscript.Expr = (m:Dynamic).__expr;
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
		case Text(_), Macro(_):
		}
	}

	function execute( obj : Model<Dynamic>, locals : {} ) {
		if( dml == null ) {
			var dom = obj.dom;
			if( dom == null )
				dom = obj.dom = Properties.create(compName,obj);
			else
				@:privateAccess dom.component = cast domkit.Component.get(compName);
			return;
		}
		interp = new ScriptInterp(this, obj, locals);
		root = obj;
		buildRec(dml, null);
		root = null;
		for( k => v in interp.variables ) {
			var l : Dynamic = Reflect.field(locals,k);
			if( l != null ) l.value = v;
		}
	}

	inline function error( msg : String, pos : { pmin : Int, pmax : Int } ) {
		throw new Error(msg,pos.pmin,pos.pmax);
	}

	function evalAttr( a : AttributeValue, pos : { pmin : Int, pmax : Int } ) : Dynamic {
		return switch( a ) {
		case RawValue(v): v;
		case Code(e): eval(e, pos);
		}
	}

	function eval( e : CodeExpr, pos : { pmin : Int, pmax : Int } ) : Dynamic {
		var expr : hscript.Expr = (pos:Dynamic).__expr;
		if( expr == null ) error("Expression was not type checked",pos);
		return interp.expr(expr);
	}

	function buildRec( m : Markup, parent : Model<Dynamic> ) {
		switch (m.kind) {
		case Node(name):

			if( m.condition != null && !eval(m.condition.cond,m.condition) )
				return;

			var attributes = {};
			var dynAttribs = [];
			var isContent = false;
			var compId = null;
			var compClass = null;
			for( a in m.attributes ) {
				switch( a.name ) {
				case "__content__": isContent = true;
				case "id":
					compId = switch( a.value ) {
					case RawValue("true"):
						var name = null;
						for( a in m.attributes )
							if( a.name == "class" ) {
								switch( a.value ) {
								case RawValue(v): name = v.split(" ")[0];
								default:
								}
							}
						name;
					default:
						evalAttr(a.value, a);
					}
				case "class" if( a.value.match(Code(_)) ): compClass = a;
				case "public": // nothing
				default:
					Reflect.setField(attributes, a.name, evalAttr(a.value,a));
				}
			}

			var compIdArray = false;
			if( compId != null ) {
				if( StringTools.endsWith(compId,"[]") ) {
					compIdArray = true;
					compId = compId.substr(0,-2);
				}
				(attributes:Dynamic).id = compId;
			}

			var dom, obj, prevObj = currentObj;
			if( parent == null ) {
				obj = root;
				dom = obj.dom;
				if( dom == null )
					dom = obj.dom = Properties.create(name,obj,attributes);
				else {
					@:privateAccess dom.component = cast domkit.Component.get(name);
					dom.initAttributes(attributes);
				}
			} else {
				var args = [for( a in m.arguments ) evalAttr(a.value,a)];
				dom = @:privateAccess Properties.createNew(name,parent.dom,args,attributes);
				obj = dom.obj;
			}
			currentObj = obj;
			if( isContent )
				@:privateAccess root.dom.contentRoot = obj;
			if( compId != null ) {
				if( compIdArray ) {
					var v : Dynamic = Reflect.getProperty(root, compId);
					if( v is Array ) v.push(obj);
				} else {
					try Reflect.setProperty(root, compId, obj) catch( e : Dynamic ) {};
				}
			}
			if( compClass != null ) {
				switch( compClass.value ) {
				case Code(e):
					var v : Dynamic = try eval(e,compClass) catch( _ : hscript.Expr.Error ) eval("{"+e+"}",{pmin:compClass.pmin-1,pmax:compClass.pmax-1});
					if( v is String )
						dom.setClasses(v);
					else
						dom.setClasses(null, v);
				default:
					throw "assert";
				}
			}
			for( c in m.children )
				buildRec(c, obj);
			currentObj = prevObj;
		case Text(text):
			var tmp = @:privateAccess domkit.Properties.createNew("text",parent.dom,[]);
			tmp.setAttribute("text",VString(text));
		case CodeBlock(expr):
			eval(expr, m);
		case For(cond):
			var expr : hscript.Expr = (m:Dynamic).__expr;
			switch( hscript.Tools.expr(expr) ) {
			case EFor(n,it,_):
				interp.executeLoop(n, it, function() {
					for( c in m.children )
						buildRec(c, parent);
				});
				return;
			case EForGen(it,_):
				hscript.Tools.getKeyIterator(it, function(vk,vv,it) {
					if( vk == null ) {
						error("Invalid for loop", m);
						return;
					}
					interp.executeKeyValueLoop(vk,vv,it,function() {
						for( c in m.children )
							buildRec(c, parent);
					});
				});
				return;
			default:
			}
			error("Invalid for loop", m);
		case Macro(id):
			error("Macro not allowed in interp mode",m);
		}
	}

	static var COMP_CACHE = new Map();
	public static function run( obj : Model<Dynamic>, compName : String, fileName : String, locals : {} ) {
		var i = COMP_CACHE.get(compName);
		if( i == null ) {
			i = new Interp(compName,fileName,locals);
			COMP_CACHE.set(compName, i);
		}
		i.execute(obj, locals);
	}

}