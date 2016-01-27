// $MinimumShaderProfile: ps_3_0

// Copyright (c) 2016, bacondither
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

// Soft limited picture controls - version 2016-01-23 - (requires ps >= 3.0)
// EXPECTS FULL RANGE GAMMA LIGHT

sampler s0 : register(s0);
float2 p1  : register(c1);

//-------------------------------------Settings--------------------------------------------

#define brightness    0.0
#define contrast      1.0               // >0
#define saturation    1.0               // >0

#define pctlim        0.95              // >0 - 1.0

//-----------------------------------------------------------------------------------------

#define soft_lim(v,s)  ( ((exp(2*min(abs(v), s*16)/s) - 1)/(exp(2*min(abs(v), s*16)/s) + 1))*s )

#define CtL(RGB)       ( sqrt(dot(float3(0.256, 0.651, 0.093), (RGB).rgb*(RGB).rgb)) )

float4 main(float2 tex : TEXCOORD0) : COLOR {

	float3 orig  = saturate(tex2D(s0, tex).rgb);

	float3 maxcolor_diff = (1.001 - orig)*pctlim;
	float3 mincolor_diff = (orig + 0.001)*pctlim;

	float luma = CtL(orig);

	float3 res = ((luma + (orig - luma)*saturation) + brightness)*contrast;

	float3 res_diff = res - orig;

	res_diff.r =  (soft_lim(max(res_diff.r, 0), maxcolor_diff.r))
	             -(soft_lim(min(res_diff.r, 0), mincolor_diff.r));

	res_diff.g =  (soft_lim(max(res_diff.g, 0), maxcolor_diff.g))
	             -(soft_lim(min(res_diff.g, 0), mincolor_diff.g));

	res_diff.b =  (soft_lim(max(res_diff.b, 0), maxcolor_diff.b))
	             -(soft_lim(min(res_diff.b, 0), mincolor_diff.b));

	return float4(orig + res_diff, 1.0);
}