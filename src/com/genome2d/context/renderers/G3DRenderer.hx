/*
 * 	Genome2D - 2D GPU Framework
 * 	http://www.genome2d.com
 *
 *	Copyright 2011-2014 Peter Stefcek. All rights reserved.
 *
 *	License:: ./doc/LICENSE.md (https://github.com/pshtif/Genome2D/blob/master/LICENSE.md)
 */
package com.genome2d.context.renderers;

import com.genome2d.context.GProjectionMatrix;
import com.genome2d.context.IGContext;
import com.genome2d.context.IGRenderer;
import com.genome2d.context.GWebGLContext;
import com.genome2d.debug.GDebug;
import com.genome2d.geom.GFloat4;
import com.genome2d.geom.GMatrix3D;
import com.genome2d.textures.GTexture;
import js.html.webgl.Texture;
import js.html.webgl.Shader;
import js.html.webgl.Program;
import js.html.webgl.Buffer;
import js.html.webgl.RenderingContext;
import js.html.webgl.UniformLocation;
import js.html.Float32Array;
import js.html.Uint16Array;

class G3DRenderer implements IGRenderer
{
	public var modelMatrix:GMatrix3D;
	public var cameraMatrix:GMatrix3D;
	public var projectionMatrix:GProjectionMatrix;
	
	private var g2d_context:GWebGLContext;
    private var g2d_nativeContext:RenderingContext;
	private var g2d_quadCount:Int = 0;
	
	private var g2d_indexBuffer:Buffer;
	private var g2d_vertexBuffer:Buffer;
	private var g2d_uvBuffer:Buffer;
	private var g2d_normalBuffer:Buffer;
	
	private var g2d_indices:Uint16Array;
    private var g2d_vertices:Float32Array;
	private var g2d_uvs:Float32Array;
	private var g2d_normals:Float32Array;

    private var g2d_activeNativeTexture:Texture;
	private var g2d_initialized:Int = -1;
	
	public var lightDirection:GFloat4;
	public var lightColor:GFloat4;
    public var ambientColor:GFloat4;
    public var tintColor:GFloat4;
	
	public var texture:GTexture;

	inline static private var VERTEX_SHADER_CODE:String = 
            "
			uniform mat4 projectionMatrix;
			uniform mat4 cameraMatrix;
			uniform mat4 modelMatrix;

			attribute vec3 aPosition;
			attribute vec2 aUv;

			varying vec2 vUv;

			void main(void)
			{
				vUv = aUv;
				gl_Position =  vec4(aPosition.x, aPosition.y, aPosition.z, 1);
				gl_Position = gl_Position * modelMatrix;
				gl_Position = gl_Position * cameraMatrix;
				gl_Position = gl_Position * projectionMatrix;
			}
		";

	inline static private var FRAGMENT_SHADER_CODE:String =
	"
			#ifdef GL_ES
			precision highp float;
			#endif

			varying vec2 vUv;

			uniform sampler2D sTexture;

			void main(void)
			{
				gl_FragColor = texture2D(sTexture, vUv);
			}
		";

	inline static private var VERTEX_SHADER_CODE_NORMAL:String =
	"
			uniform mat4 projectionMatrix;
			uniform mat4 cameraMatrix;
			uniform mat4 modelMatrix;
			uniform mat4 invertedMatrix;

			attribute vec3 aPosition;
			attribute vec2 aUv;
			attribute vec3 aNormal;

			varying vec2 vUv;
			varying vec3 vNormal;

			void main(void)
			{
				vUv = aUv;

				vNormal = (vec4(aNormal.x, aNormal.y, aNormal.z, 1) * invertedMatrix).xyz;
				vNormal = normalize(vNormal);

				gl_Position = vec4(aPosition.x, aPosition.y, aPosition.z, 1);
				gl_Position = gl_Position * modelMatrix;
				gl_Position = gl_Position * cameraMatrix;
				gl_Position = gl_Position * projectionMatrix;
			}
		";

	inline static private var FRAGMENT_SHADER_CODE_NORMAL:String =
	"
			#ifdef GL_ES
			precision highp float;
			#endif

			varying vec2 vUv;
			varying vec3 vNormal;

			uniform sampler2D sTexture;

			uniform vec3 lightDirection;
			uniform vec3 lightColor;
			uniform vec3 ambientColor;
			uniform vec4 tintColor;

			void main(void)
			{
				vec4 texColor = texture2D(sTexture, vUv);

				float light = -dot(vNormal, lightDirection);
				light = clamp(light, 0.0, 1.0);

				vec3 directionColor = texColor.xyz * light * lightColor;
				vec3 ambientColor = texColor.xyz * ambientColor.xyz;

				texColor.xyz = directionColor + ambientColor;
				gl_FragColor = tintColor * texColor;
			}
		";

	public var g2d_program:Program;

	public function getProgram() {
		return g2d_program;
	}
	
	inline public static var STRIDE : Int = 24;
	
	public function invalidateGeometry(p_vertices:Array<Float>, p_uvs:Array<Float>, p_indices:Array<UInt>, p_normals:Array<Float>):Void {
		g2d_vertices = new Float32Array(p_vertices.length);
		for (i in 0...p_vertices.length) g2d_vertices[i] = p_vertices[i];
		
		g2d_uvs = new Float32Array(p_uvs.length);
		for (i in 0...p_uvs.length) g2d_uvs[i] = p_uvs[i];

		g2d_normals = new Float32Array(p_normals.length);
		for (i in 0...p_normals.length) g2d_normals[i] = p_normals[i];
		
		g2d_indices = new Uint16Array(p_indices.length);
		for (i in 0...p_indices.length) g2d_indices[i] = p_indices[i];
	}
	
	public function new(p_vertices:Array<Float>, p_uvs:Array<Float>, p_indices:Array<UInt>, p_normals:Array<Float>, p_generatePerspectiveMatrix:Bool = false):Void {
		invalidateGeometry(p_vertices, p_uvs, p_indices, p_normals);
		
		modelMatrix = new GMatrix3D();
		cameraMatrix = new GMatrix3D();
		lightDirection = new GFloat4();
    }

    private function getShader(shaderSrc:String, shaderType:Int):Shader {
        var shader:Shader = g2d_nativeContext.createShader(shaderType);
        g2d_nativeContext.shaderSource(shader, shaderSrc);
        g2d_nativeContext.compileShader(shader);

        if (!g2d_nativeContext.getShaderParameter(shader, RenderingContext.COMPILE_STATUS)) {
            GDebug.error("Shader compilation error: " + g2d_nativeContext.getShaderInfoLog(shader)); return null;
        }
		
        return shader;
    }

    public function initialize(p_context:GWebGLContext):Void {
		g2d_context = p_context;
		g2d_nativeContext = g2d_context.getNativeContext();
		
		var fragmentShader = getShader(FRAGMENT_SHADER_CODE_NORMAL, RenderingContext.FRAGMENT_SHADER);
		var vertexShader = getShader(VERTEX_SHADER_CODE_NORMAL, RenderingContext.VERTEX_SHADER);

		g2d_program = g2d_nativeContext.createProgram();
		g2d_nativeContext.attachShader(g2d_program, vertexShader);
		g2d_nativeContext.attachShader(g2d_program, fragmentShader);
		g2d_nativeContext.linkProgram(g2d_program);

		//if (!RenderingContext.getProgramParameter(program, RenderingContext.LINK_STATUS)) { ("Could not initialise shaders"); }

		g2d_nativeContext.useProgram(g2d_program);

		untyped g2d_program.positionAttribute = g2d_nativeContext.getAttribLocation(g2d_program, "aPosition");
		untyped g2d_nativeContext.enableVertexAttribArray(g2d_program.positionAttribute);
		
		untyped g2d_program.uvAttribute = g2d_nativeContext.getAttribLocation(g2d_program, "aUv");
		untyped g2d_nativeContext.enableVertexAttribArray(g2d_program.uvAttribute);

		untyped g2d_program.normalAttribute = g2d_nativeContext.getAttribLocation(g2d_program, "aNormal");
		untyped g2d_nativeContext.enableVertexAttribArray(g2d_program.normalAttribute);
		
		untyped g2d_program.samplerUniform = g2d_nativeContext.getUniformLocation(g2d_program, "sTexture");
		
		g2d_indexBuffer = g2d_nativeContext.createBuffer();
        g2d_vertexBuffer = g2d_nativeContext.createBuffer();
		g2d_uvBuffer = g2d_nativeContext.createBuffer();
		g2d_normalBuffer = g2d_nativeContext.createBuffer();
	}

	@:access(com.genome2d.context.GWebGLContext)
    public function bind(p_context:IGContext, p_reinitialize:Int):Void {
		if (p_reinitialize != g2d_initialized) initialize(cast p_context);
		g2d_initialized = p_reinitialize;
		
		g2d_nativeContext.useProgram(g2d_program);
		p_context.setDepthTest(true, GDepthFunc.LESS);
		g2d_nativeContext.enable(RenderingContext.CULL_FACE);
    }
	
	@:access(com.genome2d.context.GWebGLContext)
	public function draw(p_cull:Int = 0, p_renderType:Int):Void {
		if (p_cull == 2) g2d_nativeContext.cullFace(RenderingContext.BACK);
        else if (p_cull == 1) g2d_nativeContext.cullFace(RenderingContext.FRONT);
		
		if (projectionMatrix != null) {
			g2d_nativeContext.uniformMatrix4fv(g2d_nativeContext.getUniformLocation(g2d_program, "projectionMatrix"), false,  projectionMatrix.rawData);
		} else {
			g2d_nativeContext.uniformMatrix4fv(g2d_nativeContext.getUniformLocation(g2d_program, "projectionMatrix"), false,  g2d_context.g2d_projectionMatrix.rawData);
		}
		
		// TODO probably not a good solution but WebGL doesn't support transpose parameter for uniformMatrix4fv due to ES2 limitations, possible solutions can also conflict with feature parity
		var transposedMatrix:GMatrix3D = modelMatrix.clone();
		transposedMatrix.transpose();
		g2d_nativeContext.uniformMatrix4fv(g2d_nativeContext.getUniformLocation(g2d_program, "modelMatrix"), false,  transposedMatrix.rawData);
		transposedMatrix = cameraMatrix.clone();
		transposedMatrix.transpose();
		g2d_nativeContext.uniformMatrix4fv(g2d_nativeContext.getUniformLocation(g2d_program, "cameraMatrix"), false,  transposedMatrix.rawData);
		transposedMatrix = modelMatrix.clone();
		transposedMatrix.invert();
		g2d_nativeContext.uniformMatrix4fv(g2d_nativeContext.getUniformLocation(g2d_program, "invertedMatrix"), false,  transposedMatrix.rawData);

		g2d_nativeContext.uniform3f(g2d_nativeContext.getUniformLocation(g2d_program, "lightDirection"), lightDirection.x, lightDirection.y, lightDirection.z);
		g2d_nativeContext.uniform3f(g2d_nativeContext.getUniformLocation(g2d_program, "lightColor"), lightColor.x, lightColor.y, lightColor.z);
		g2d_nativeContext.uniform3f(g2d_nativeContext.getUniformLocation(g2d_program, "ambientColor"), ambientColor.x, ambientColor.y, ambientColor.z);
		g2d_nativeContext.uniform4f(g2d_nativeContext.getUniformLocation(g2d_program, "tintColor"), tintColor.x * tintColor.w, tintColor.y * tintColor.w, tintColor.z * tintColor.w, tintColor.w);
		
		g2d_activeNativeTexture = texture.nativeTexture;
		g2d_nativeContext.activeTexture(RenderingContext.TEXTURE0);
		g2d_nativeContext.bindTexture(RenderingContext.TEXTURE_2D, texture.nativeTexture);
		untyped g2d_nativeContext.uniform1i(g2d_program.samplerUniform, 0);

        g2d_nativeContext.bindBuffer(RenderingContext.ARRAY_BUFFER, g2d_vertexBuffer);
        g2d_nativeContext.bufferData(RenderingContext.ARRAY_BUFFER, g2d_vertices, RenderingContext.STREAM_DRAW);
		untyped g2d_nativeContext.vertexAttribPointer(g2d_program.positionAttribute, 3, RenderingContext.FLOAT, false, 0, 0);
		//GDebug.info("Vertices:", g2d_vertices.length);
		
		g2d_nativeContext.bindBuffer(RenderingContext.ARRAY_BUFFER, g2d_uvBuffer);
        g2d_nativeContext.bufferData(RenderingContext.ARRAY_BUFFER, g2d_uvs, RenderingContext.STREAM_DRAW);
		untyped g2d_nativeContext.vertexAttribPointer(g2d_program.uvAttribute, 2, RenderingContext.FLOAT, false, 0, 0);
		//GDebug.info("UVs:", g2d_uvs.length);

		g2d_nativeContext.bindBuffer(RenderingContext.ARRAY_BUFFER, g2d_normalBuffer);
		g2d_nativeContext.bufferData(RenderingContext.ARRAY_BUFFER, g2d_normals, RenderingContext.STREAM_DRAW);
		untyped g2d_nativeContext.vertexAttribPointer(g2d_program.normalAttribute, 3, RenderingContext.FLOAT, false, 0, 0);
		//GDebug.info("Normals:", g2d_normals.length);
		
		g2d_nativeContext.bindBuffer(RenderingContext.ELEMENT_ARRAY_BUFFER, g2d_indexBuffer);
        g2d_nativeContext.bufferData(RenderingContext.ELEMENT_ARRAY_BUFFER, g2d_indices, RenderingContext.STATIC_DRAW);
		//GDebug.info("Indices:", g2d_indices.length);

		g2d_nativeContext.drawElements(RenderingContext.TRIANGLES, g2d_indices.length, RenderingContext.UNSIGNED_SHORT, 0);
    }
	
	public function push():Void {
		
	}

    public function clear():Void {
        g2d_activeNativeTexture = null;

		g2d_context.setDepthTest(false, GDepthFunc.ALWAYS);
		g2d_nativeContext.disable(RenderingContext.CULL_FACE);
    }
	
	public function dispose():Void {
		g2d_nativeContext.deleteBuffer(g2d_indexBuffer);
		g2d_nativeContext.deleteBuffer(g2d_vertexBuffer);
		g2d_nativeContext.deleteBuffer(g2d_uvBuffer);
		g2d_nativeContext.deleteBuffer(g2d_normalBuffer);
		
		g2d_nativeContext.deleteProgram(g2d_program);
	}
}