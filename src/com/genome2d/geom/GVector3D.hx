package com.genome2d.geom;

class GVector3D {
	static public var X_AXIS(get, null):GVector3D;
	inline static private function get_X_AXIS ():GVector3D {
		return new GVector3D (1, 0, 0);
	}
	
	static public var Y_AXIS (get, null):GVector3D;	
	inline static private function get_Y_AXIS ():GVector3D {
		return new GVector3D (0, 1, 0);
	}
	
	static public var Z_AXIS (get, null):GVector3D;	
	inline static private function get_Z_AXIS ():GVector3D {
		return new GVector3D (0, 0, 1);
	}
	
    public var x:Float;
    public var y:Float;
    public var z:Float;

    public function new(p_x:Float = 0, p_y:Float = 0, p_z:Float = 0) {
        x = p_x;
        y = p_y;
        z = p_z;
    }
}