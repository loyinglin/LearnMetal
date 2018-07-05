//
//  Created by loyinglin on 2018年06月29日.
//  Copyright © 2018年 loyinglin. All rights reserved.
//

varying highp vec2 texCoordVarying;
uniform sampler2D inputTexture;
precision mediump float;

void main()
{
	lowp vec3 rgb = texture2D(inputTexture, texCoordVarying).rgb;
    gl_FragColor = vec4(rgb, 1);
}
