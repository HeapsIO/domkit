package domkit;

abstract Identifier(Int) {
	public function new(name:String) {
		this = _CACHE.get(name);
		if( this == 0 ) {
			this = ++_UID;
			_CACHE.set(name, this);
			_RCACHE.push(name);
		}
	}
	public function toString() {
		return _RCACHE[this];
	}
	public inline function isDefined() {
		return this != 0;
	}
	static var _UID = 0;
	static var _CACHE = new Map();
	static var _RCACHE = [null];
}