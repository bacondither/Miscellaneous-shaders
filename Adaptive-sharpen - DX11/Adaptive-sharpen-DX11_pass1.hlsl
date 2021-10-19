// $MinimumShaderProfile: ps_4_0

// Copyright (c) 2015-2021, bacondither
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer
//    in this position and unchanged.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE AUTHORS ``AS IS'' AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
// IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
// NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
// THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

// First pass, MUST BE PLACED IMMEDIATELY BEFORE THE SECOND PASS IN THE CHAIN

// Adaptive sharpen - version DX11 - 2021-09-10
// Tuned for use post-resize, EXPECTS FULL RANGE GAMMA LIGHT (requires ps >= 4.0)

//============================== Settings =============================================

#define fast_length  0           // Fast length using aproximate sqrt
//-------------------------------------------------------------------------------------
#define a_offset     2.0         // Edge channel offset, MUST BE THE SAME IN ALL PASSES

//=====================================================================================

Texture2D tex     : register(t0);
SamplerState samp : register(s0);

cbuffer PS_CONSTANTS : register(b0) { float2 pxy; };

// Get destination pixel values
#define get(x,y)    ( saturate(tex.Sample(samp, pxy*float2(x, y) + coord).rgb) )

// Component-wise distance
#define b_diff(pix) ( abs(blur - c[pix]) )

#if (fast_length == 1)
	#define LENGTH(v)      ( asfloat(0x1FBD1DF5 + (asint(dot(v, v)) >> 1)) )
#else
	#define LENGTH(v)      ( length(v) )
#endif

float4 main(float4 pos : SV_POSITION, float2 coord : TEXCOORD) : SV_Target
{
	float3 cO = tex.Sample(samp, coord).rgb;

	// Get points and clip out of range values (BTB & WTW)
	// [                c9                ]
	// [           c1,  c2,  c3           ]
	// [      c10, c4,  c0,  c5, c11      ]
	// [           c6,  c7,  c8           ]
	// [                c12               ]
	float3 c[13] = { saturate(cO), get(-1,-1), get( 0,-1), get( 1,-1), get(-1, 0),
	                   get( 1, 0), get(-1, 1), get( 0, 1), get( 1, 1), get( 0,-2),
	                   get(-2, 0), get( 2, 0), get( 0, 2) };

	// Gauss blur 3x3
	float3 blur = (2*(c[2]+c[4]+c[5]+c[7]) + (c[1]+c[3]+c[6]+c[8]) + 4*c[0])/16;

	// Contrast compression, center = 0.5, scaled to 1/3
	float c_comp = saturate(4.0/15.0 + 0.9*exp2(dot(blur, -37.0/15.0)));

	// Edge detection
	// Relative matrix weights
	// [          1          ]
	// [      4,  5,  4      ]
	// [  1,  5,  6,  5,  1  ]
	// [      4,  5,  4      ]
	// [          1          ]
	float edge = LENGTH( 1.38*(b_diff(0))
	                   + 1.15*(b_diff(2) + b_diff(4)  + b_diff(5)  + b_diff(7))
	                   + 0.92*(b_diff(1) + b_diff(3)  + b_diff(6)  + b_diff(8))
	                   + 0.23*(b_diff(9) + b_diff(10) + b_diff(11) + b_diff(12)) );

	return float4( cO, edge*c_comp + a_offset );
}