//
//  Created by loyinglin on 2018年06月29日.
//  Copyright © 2018年 loyinglin. All rights reserved.
//

varying highp vec2 texCoordVarying;
uniform sampler2D inputTexture;
precision mediump float;

void main()
{
	lowp vec4 rgba = texture2D(inputTexture, texCoordVarying).bgra;
    gl_FragColor = rgba;
}
