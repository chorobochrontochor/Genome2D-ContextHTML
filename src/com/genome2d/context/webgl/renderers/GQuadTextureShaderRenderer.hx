/*
 * 	Genome2D - 2D GPU Framework
 * 	http://www.genome2d.com
 *
 *	Copyright 2011-2014 Peter Stefcek. All rights reserved.
 *
 *	License:: ./doc/LICENSE.md (https://github.com/pshtif/Genome2D/blob/master/LICENSE.md)
 */
package com.genome2d.context.webgl.renderers;

import com.genome2d.context.stats.GStats;
import com.genome2d.context.webgl.renderers.IGRenderer;
import js.html.Uint16Array;
import js.html.webgl.Texture;
import js.html.webgl.Shader;
import js.html.webgl.Program;
import js.html.webgl.Buffer;
import js.html.webgl.RenderingContext;
import js.html.webgl.UniformLocation;
import com.genome2d.textures.GContextTexture;
import js.html.Float32Array;

class GQuadTextureShaderRenderer implements IGRenderer
{
    inline static private var BATCH_SIZE:Int = 30;

    inline static private var TRANSFORM_PER_VERTEX:Int = 3;
    inline static private var TRANSFORM_PER_VERTEX_ALPHA:Int = TRANSFORM_PER_VERTEX+1;

    /*
    inline static private var VERTEX_SHADER_CODE:String =
    "
			uniform mat4 projectionMatrix;
			uniform vec4 transforms["+BATCH_SIZE*TRANSFORM_PER_VERTEX+"];

			attribute vec2 aPosition;
			attribute vec2 aTexCoord;
			attribute vec3 aConstantIndex;

			varying vec2 vTexCoord;

			void main(void)
			{
				gl_Position = vec4(aPosition.x*transforms[int(aConstantIndex.z)].x, aPosition.y*transforms[int(aConstantIndex.z)].y, 0, 1);
				gl_Position = vec4(gl_Position.x - transforms[int(aConstantIndex.z)].z, gl_Position.y - transforms[int(aConstantIndex.z)].w, 0, 1);
				float c = cos(transforms[int(aConstantIndex.x)].z);
				float s = sin(transforms[int(aConstantIndex.x)].z);
				gl_Position = vec4(gl_Position.x * c - gl_Position.y * s, gl_Position.x * s + gl_Position.y * c, 0, 1);
				gl_Position = vec4(gl_Position.x+transforms[int(aConstantIndex.x)].x, gl_Position.y+transforms[int(aConstantIndex.x)].y, 0, 1);
				gl_Position = gl_Position * projectionMatrix;

				vTexCoord = vec2(aTexCoord.x*transforms[int(aConstantIndex.y)].z+transforms[int(aConstantIndex.y)].x, aTexCoord.y*transforms[int(aConstantIndex.y)].w+transforms[int(aConstantIndex.y)].y);
			}
		 ";

    inline static private var FRAGMENT_SHADER_CODE:String =
    "
			#ifdef GL_ES
			precision highp float;
			#endif

			varying vec2 vTexCoord;

			uniform sampler2D sTexture;

			void main(void)
			{
				vec4 texColor;
				texColor = texture2D(sTexture, vTexCoord);
				gl_FragColor = texColor;
			}
		";
    /**/
    inline static private var VERTEX_SHADER_CODE_ALPHA:String =
    "
			uniform mat4 projectionMatrix;
			uniform vec4 transforms["+BATCH_SIZE*TRANSFORM_PER_VERTEX_ALPHA+"];

			attribute vec2 aPosition;
			attribute vec2 aTexCoord;
			attribute vec4 aConstantIndex;

			varying vec2 vTexCoord;
			varying vec4 vColor;

			void main(void)
			{
				gl_Position = vec4(aPosition.x*transforms[int(aConstantIndex.z)].x, aPosition.y*transforms[int(aConstantIndex.z)].y, 0, 1);
				gl_Position = vec4(gl_Position.x - transforms[int(aConstantIndex.z)].z, gl_Position.y - transforms[int(aConstantIndex.z)].w, 0, 1);
				float c = cos(transforms[int(aConstantIndex.x)].z);
				float s = sin(transforms[int(aConstantIndex.x)].z);
				gl_Position = vec4(gl_Position.x * c - gl_Position.y * s, gl_Position.x * s + gl_Position.y * c, 0, 1);
				gl_Position = vec4(gl_Position.x+transforms[int(aConstantIndex.x)].x, gl_Position.y+transforms[int(aConstantIndex.x)].y, 0, 1);
				gl_Position = gl_Position * projectionMatrix;

				vTexCoord = vec2(aTexCoord.x*transforms[int(aConstantIndex.y)].z+transforms[int(aConstantIndex.y)].x, aTexCoord.y*transforms[int(aConstantIndex.y)].w+transforms[int(aConstantIndex.y)].y);
				vColor = transforms[int(aConstantIndex.w)];
			}
		 ";

    inline static private var FRAGMENT_SHADER_CODE_ALPHA:String =
    "
			//#ifdef GL_ES
			precision lowp float;
			//#endif

			varying vec2 vTexCoord;
			varying vec4 vColor;

			uniform sampler2D sTexture;

			void main(void)
			{
				gl_FragColor = texture2D(sTexture, vTexCoord) * vColor;
			}
		";

    private var g2d_nativeContext:RenderingContext;
	private var g2d_quadCount:Int = 0;
	
	private var g2d_geometryBuffer:Buffer;
    private var g2d_uvBuffer:Buffer;
    private var g2d_constantIndexBuffer:Buffer;
    private var g2d_constantIndexAlphaBuffer:Buffer;

    private var g2d_indexBuffer:Buffer;

    private var g2d_activeNativeTexture:Texture;
    private var g2d_activeAlpha:Bool = false;

    private var g2d_useSeparatedAlphaPipeline:Bool = false;

    private var g2d_transforms:Float32Array;
    private var g2d_context:GWebGLContext;

    private var g2d_initialized:Bool;

	public var g2d_program:Dynamic;
	
	public function new():Void {
        g2d_initialized = false;
    }

    private function getShader(shaderSrc:String, shaderType:Int):Shader {
        var shader:Shader = g2d_nativeContext.createShader(shaderType);
        g2d_nativeContext.shaderSource(shader, shaderSrc);
        g2d_nativeContext.compileShader(shader);

        // Check for erros
        if (!g2d_nativeContext.getShaderParameter(shader, RenderingContext.COMPILE_STATUS)) {
            trace("Shader compilation error: " + g2d_nativeContext.getShaderInfoLog(shader)); return null;
        }
        /**/
        return shader;
    }

    public function initialize(p_context:GWebGLContext):Void {
        g2d_context = p_context;
		g2d_nativeContext = g2d_context.getNativeContext();

        trace(g2d_nativeContext.getParameter(RenderingContext.MAX_VERTEX_UNIFORM_VECTORS));
		
		var fragmentShader = getShader(FRAGMENT_SHADER_CODE_ALPHA, RenderingContext.FRAGMENT_SHADER);
		var vertexShader = getShader(VERTEX_SHADER_CODE_ALPHA, RenderingContext.VERTEX_SHADER);

		g2d_program = g2d_nativeContext.createProgram();
		g2d_nativeContext.attachShader(g2d_program, vertexShader);
		g2d_nativeContext.attachShader(g2d_program, fragmentShader);
		g2d_nativeContext.linkProgram(g2d_program);

		//if (!RenderingContext.getProgramParameter(program, RenderingContext.LINK_STATUS)) { trace("Could not initialise shaders"); }

		g2d_nativeContext.useProgram(g2d_program);

        var vertices:Float32Array = new Float32Array(8*BATCH_SIZE);
        var uvs:Float32Array = new Float32Array(8*BATCH_SIZE);
        var registerIndices:Float32Array = new Float32Array(TRANSFORM_PER_VERTEX*BATCH_SIZE*4);
        var registerIndicesAlpha:Float32Array = new Float32Array(TRANSFORM_PER_VERTEX_ALPHA*BATCH_SIZE*4);

        for (i in 0...BATCH_SIZE) {
            vertices[i*8] = GRendererCommon.NORMALIZED_VERTICES[0];
            vertices[i*8+1] = GRendererCommon.NORMALIZED_VERTICES[1];
            vertices[i*8+2] = GRendererCommon.NORMALIZED_VERTICES[2];
            vertices[i*8+3] = GRendererCommon.NORMALIZED_VERTICES[3];
            vertices[i*8+4] = GRendererCommon.NORMALIZED_VERTICES[4];
            vertices[i*8+5] = GRendererCommon.NORMALIZED_VERTICES[5];
            vertices[i*8+6] = GRendererCommon.NORMALIZED_VERTICES[6];
            vertices[i*8+7] = GRendererCommon.NORMALIZED_VERTICES[7];

            uvs[i*8] = GRendererCommon.NORMALIZED_UVS[0];
            uvs[i*8+1] = GRendererCommon.NORMALIZED_UVS[1];
            uvs[i*8+2] = GRendererCommon.NORMALIZED_UVS[2];
            uvs[i*8+3] = GRendererCommon.NORMALIZED_UVS[3];
            uvs[i*8+4] = GRendererCommon.NORMALIZED_UVS[4];
            uvs[i*8+5] = GRendererCommon.NORMALIZED_UVS[5];
            uvs[i*8+6] = GRendererCommon.NORMALIZED_UVS[6];
            uvs[i*8+7] = GRendererCommon.NORMALIZED_UVS[7];

            var index:Int = (i * TRANSFORM_PER_VERTEX);
            registerIndices[index*4] = index;
            registerIndices[index*4+1] = index+1;
            registerIndices[index*4+2] = index+2;
            registerIndices[index*4+3] = index;
            registerIndices[index*4+4] = index+1;
            registerIndices[index*4+5] = index+2;
            registerIndices[index*4+6] = index;
            registerIndices[index*4+7] = index+1;
            registerIndices[index*4+8] = index+2;
            registerIndices[index*4+9] = index;
            registerIndices[index*4+10] = index+1;
            registerIndices[index*4+11] = index+2;

            var index:Int = (i * TRANSFORM_PER_VERTEX_ALPHA);
            registerIndicesAlpha[index*4] = index;
            registerIndicesAlpha[index*4+1] = index+1;
            registerIndicesAlpha[index*4+2] = index+2;
            registerIndicesAlpha[index*4+3] = index+3;
            registerIndicesAlpha[index*4+4] = index;
            registerIndicesAlpha[index*4+5] = index+1;
            registerIndicesAlpha[index*4+6] = index+2;
            registerIndicesAlpha[index*4+7] = index+3;
            registerIndicesAlpha[index*4+8] = index;
            registerIndicesAlpha[index*4+9] = index+1;
            registerIndicesAlpha[index*4+10] = index+2;
            registerIndicesAlpha[index*4+11] = index+3;
            registerIndicesAlpha[index*4+12] = index;
            registerIndicesAlpha[index*4+13] = index+1;
            registerIndicesAlpha[index*4+14] = index+2;
            registerIndicesAlpha[index*4+15] = index+3;
        }

        g2d_geometryBuffer = g2d_nativeContext.createBuffer();
        g2d_nativeContext.bindBuffer(RenderingContext.ARRAY_BUFFER, g2d_geometryBuffer);
        g2d_nativeContext.bufferData(RenderingContext.ARRAY_BUFFER, vertices, RenderingContext.STREAM_DRAW);

        g2d_uvBuffer = g2d_nativeContext.createBuffer();
        g2d_nativeContext.bindBuffer(RenderingContext.ARRAY_BUFFER, g2d_uvBuffer);
        g2d_nativeContext.bufferData(RenderingContext.ARRAY_BUFFER, uvs, RenderingContext.STREAM_DRAW);

        g2d_constantIndexBuffer = g2d_nativeContext.createBuffer();
        g2d_nativeContext.bindBuffer(RenderingContext.ARRAY_BUFFER, g2d_constantIndexBuffer);
        g2d_nativeContext.bufferData(RenderingContext.ARRAY_BUFFER, registerIndices, RenderingContext.STREAM_DRAW);

        g2d_constantIndexAlphaBuffer = g2d_nativeContext.createBuffer();
        g2d_nativeContext.bindBuffer(RenderingContext.ARRAY_BUFFER, g2d_constantIndexAlphaBuffer);
        g2d_nativeContext.bufferData(RenderingContext.ARRAY_BUFFER, registerIndicesAlpha, RenderingContext.STREAM_DRAW);

        var indices:Uint16Array = new Uint16Array(BATCH_SIZE * 6);
        for (i in 0...BATCH_SIZE) {
            var ao:Int = i*6;
            var io:Int = i*4;
            indices[ao] = io;
            indices[ao+1] = io+1;
            indices[ao+2] = io+2;
            indices[ao+3] = io;
            indices[ao+4] = io+2;
            indices[ao+5] = io+3;
        }

        g2d_indexBuffer = g2d_nativeContext.createBuffer();
        g2d_nativeContext.bindBuffer(RenderingContext.ELEMENT_ARRAY_BUFFER, g2d_indexBuffer);
        g2d_nativeContext.bufferData(RenderingContext.ELEMENT_ARRAY_BUFFER, indices, RenderingContext.STATIC_DRAW);

		g2d_program.samplerUniform = g2d_nativeContext.getUniformLocation(g2d_program, "sTexture");

        g2d_program.positionAttribute = g2d_nativeContext.getAttribLocation(g2d_program, "aPosition");
        g2d_nativeContext.enableVertexAttribArray(g2d_program.positionAttribute);

        g2d_program.texCoordAttribute = g2d_nativeContext.getAttribLocation(g2d_program, "aTexCoord");
        g2d_nativeContext.enableVertexAttribArray(g2d_program.texCoordAttribute);

        g2d_program.constantIndexAttribute = g2d_nativeContext.getAttribLocation(g2d_program, "aConstantIndex");
        g2d_nativeContext.enableVertexAttribArray(g2d_program.constantIndexAttribute);

        g2d_transforms = new Float32Array(BATCH_SIZE*TRANSFORM_PER_VERTEX_ALPHA*4);
        g2d_initialized = true;
	}

    @:access(com.genome2d.context.webgl.GWebGLContext)
    public function bind(p_context:GWebGLContext, p_reinitialize:Bool):Void {
        if (!g2d_initialized || p_reinitialize) initialize(p_context);
        // Bind camera matrix
        g2d_nativeContext.uniformMatrix4fv(g2d_nativeContext.getUniformLocation(g2d_program, "projectionMatrix"), false,  g2d_context.g2d_projectionMatrix);

        g2d_nativeContext.bindBuffer(RenderingContext.ELEMENT_ARRAY_BUFFER, g2d_indexBuffer);

        g2d_nativeContext.bindBuffer(RenderingContext.ARRAY_BUFFER, g2d_geometryBuffer);
        g2d_nativeContext.vertexAttribPointer(g2d_program.positionAttribute, 2, RenderingContext.FLOAT, false, 0, 0);

        g2d_nativeContext.bindBuffer(RenderingContext.ARRAY_BUFFER, g2d_uvBuffer);
        g2d_nativeContext.vertexAttribPointer(g2d_program.texCoordAttribute, 2, RenderingContext.FLOAT, false, 0, 0);

        g2d_nativeContext.bindBuffer(RenderingContext.ARRAY_BUFFER, g2d_constantIndexAlphaBuffer);
        g2d_nativeContext.vertexAttribPointer(g2d_program.constantIndexAttribute, 4, RenderingContext.FLOAT, false, 0, 0);
    }
	
	inline public function draw(p_x:Float, p_y:Float, p_scaleX:Float, p_scaleY:Float, p_rotation:Float, p_red:Float, p_green:Float, p_blue:Float, p_alpha:Float, p_texture:GContextTexture):Void {
        var notSameTexture:Bool = g2d_activeNativeTexture != p_texture.nativeTexture;
        var useAlpha:Bool = !g2d_useSeparatedAlphaPipeline && !(p_red==1 && p_green==1 && p_blue==1 && p_alpha==1);
        var notSameUseAlpha:Bool = g2d_activeAlpha != useAlpha;
        // TODO: Change this if we implement separate alpha pipeline
        g2d_activeAlpha = useAlpha;

        if (notSameTexture) {
            if (g2d_activeNativeTexture != null) push();

            if (notSameTexture) {
                g2d_activeNativeTexture = p_texture.nativeTexture;
                g2d_nativeContext.activeTexture(RenderingContext.TEXTURE0);
                g2d_nativeContext.bindTexture(RenderingContext.TEXTURE_2D, p_texture.nativeTexture);
                untyped g2d_nativeContext.uniform1i(g2d_program.samplerUniform, 0);
            }
        }

        // Alpha is active and texture uses premultiplied source
        if (g2d_activeAlpha) {
            p_red*=p_alpha;
            p_green*=p_alpha;
            p_blue*=p_alpha;
        }
        /**/

        var offset:Int = g2d_quadCount*TRANSFORM_PER_VERTEX_ALPHA<<2;
        g2d_transforms[offset] = p_x;
        g2d_transforms[offset+1] = p_y;
        g2d_transforms[offset+2] = p_rotation;
        g2d_transforms[offset+3] = 0; // Reserved for id

        g2d_transforms[offset+4] = p_texture.uvX;
        g2d_transforms[offset+5] = p_texture.uvY;
        g2d_transforms[offset+6] = p_texture.uvScaleX;
        g2d_transforms[offset+7] = p_texture.uvScaleY;

        g2d_transforms[offset+8] = p_scaleX*p_texture.width;
        g2d_transforms[offset+9] = p_scaleY*p_texture.height;
        g2d_transforms[offset+10] = p_scaleX*p_texture.pivotX;
        g2d_transforms[offset+11] = p_scaleY*p_texture.pivotY;

        g2d_transforms[offset+12] = p_red;
        g2d_transforms[offset+13] = p_green;
        g2d_transforms[offset+14] = p_blue;
        g2d_transforms[offset+15] = p_alpha;

		g2d_quadCount++;

        if (g2d_quadCount == BATCH_SIZE) push();
	}
	
	inline public function push():Void {
        if (g2d_quadCount>0) {
            GStats.drawCalls++;
            g2d_nativeContext.uniform4fv(g2d_nativeContext.getUniformLocation(g2d_program, "transforms"), g2d_transforms);

            g2d_nativeContext.drawElements(RenderingContext.TRIANGLES, 6*g2d_quadCount, RenderingContext.UNSIGNED_SHORT, 0);

            g2d_quadCount = 0;
        }
    }

    public function clear():Void {
        g2d_activeNativeTexture = null;
    }
}