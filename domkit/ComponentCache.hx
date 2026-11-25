package domkit;

#if macro
#if haxe6
// the component of each component class, given by its build
typedef ComponentCache = haxe.macro.TypeCache<MetaComponent>;
#else
// the same API as haxe.macro.TypeCache (Haxe 6), kept by the macro context
class ComponentCache {

	var values = new Map<String, MetaComponent>();

	public function new() {
	}

	static function key( t : haxe.macro.Type ) {
		return switch( t ) {
		case TInst(c, _): c.toString();
		default: null;
		}
	}

	public function setCurrent( value : MetaComponent ) {
		values.set(key(haxe.macro.Context.getLocalType()), value);
	}

	public function tryGet( t : haxe.macro.Type ) : MetaComponent {
		var k = key(t);
		if( k == null ) return null;
		// builds the class: its build gives its component
		switch( t ) {
		case TInst(c, _): c.get();
		default:
		}
		return values.get(k);
	}

	public function all() : Array<{ type : haxe.macro.Type, value : MetaComponent }> {
		var keys = [for( k in values.keys() ) k];
		keys.sort(Reflect.compare);
		return [for( k in keys ) { type : haxe.macro.Context.getType(k), value : values.get(k) }];
	}
}
#end
#end
