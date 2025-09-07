package domkit;
import domkit.MarkupParser;

#if hscript
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
				var dml = Reflect.field(e,"dml");
				if( dml == null ) {
					var parser = new MarkupParser();
					dml = parser.parse(data,@:privateAccess ctx.filePath,#if hscriptPos e.pmin #else 0 #end).children[0];
					Reflect.setField(e,"dml",dml);
				}
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
		if( Reflect.hasField(objLocals,id) )
			return Reflect.field(objLocals,id);
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
#end

class Interp {

	public static var enable : Bool = false;
	public static var SRC_PATHS = ["."];

	var compName : String;
	var fileName : String;
	var filePath : String;
	var dml : Markup;
	var root : Model<Dynamic>;
	var currentObj : Model<Dynamic>;
	#if hscript
	var parser : hscript.Parser;
	var interp : ScriptInterp;
	#end

	function new( compName, fileName ) {
		this.compName = compName;
		this.fileName = fileName;
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
		#if hscript
		parser = new hscript.Parser();
		interp = new ScriptInterp(this, obj, locals);
		#end
		root = obj;
		buildRec(dml, null);
		root = null;
		#if hscript
		for( k => v in interp.variables )
			if( Reflect.hasField(locals,k) )
				Reflect.setField(locals,k,v);
		#end
	}

	function error( msg : String, pos : { pmin : Int, pmax : Int } ) {
		throw new Error(msg,pos.pmin,pos.pmax);
	}

	function evalAttr( a : AttributeValue, pos : { pmin : Int, pmax : Int } ) : Dynamic {
		return switch( a ) {
		case RawValue(v): v;
		case Code(e): eval(e, pos);
		}
	}

	function eval( e : CodeExpr, pos : { pmin : Int, pmax : Int } ) : Dynamic {
		#if !hscript
		error("Cannot eval code without -lib hscript", pos);
		return null;
		#else
		var expr = parser.parseString(e,fileName,pos.pmin);
		return interp.expr(expr);
		#end
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
			#if !hscript
			eval(cond, m);
			#else
			var expr = parser.parseString("for"+cond+"{}",fileName,m.pmin);
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
			#end
		case Macro(id):
			error("Macro not allowed in interp mode",m);
		}
	}

	static var COMP_CACHE = new Map();
	public static function run( obj : Model<Dynamic>, compName : String, fileName : String, locals : {} ) {
		var i = COMP_CACHE.get(compName);
		if( i == null ) {
			i = new Interp(compName,fileName);
			COMP_CACHE.set(compName, i);
		}
		i.execute(obj, locals);
	}

}