//
//  Created by loyinglin on 2018年06月29日.
//  Copyright © 2018年 loyinglin. All rights reserved.
//

attribute vec4 position;
attribute vec2 texCoord;
varying vec2 texCoordVarying;

void main()
{
    gl_Position = position;
    texCoordVarying = texCoord;
}

