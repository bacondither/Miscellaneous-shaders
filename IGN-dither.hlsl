// $MinimumShaderProfile: ps_3_0

// Copyright (c) 2021, bacondither
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

// Interleaved Gradient Noise dither - version 2021-08-26 - (requires ps >= 3.0)
// EXPECTS FULL RANGE GAMMA LIGHT

sampler s0 : register(s0);
float4 p0  : register(c0);

//================================== Settings =====================================================

#define backbuffer_bits    8.0          // Backbuffer bith depth, most likely 8 or 10 bits
#define col_noise          1            // Coloured dither noise, lower subjective noise level
#define temporal_dither    1            // Dither changes with every frame
//-------------------------------------------------------------------------------------------------
#define quant_to_bit_depth 0            // Quantize to target bitdepth
//-------------------------------------------------------------------------------------------------
#define alpha_out          1.0          // MPDN requires alpha channel output to be 1.0

//=================================================================================================

#define qrand(x) frac(sin(x)*43758.5453123)

float4 main(float4 pos : SV_Position, float2 tex : TEXCOORD0) : COLOR
{
	float3 c0 = tex2D(s0, tex).rgb;

	float colsteps = exp2(backbuffer_bits) - 1;

	// Interleaved gradient noise by Jorge Jimenez
	const float3 magic = float3(0.06711056, 0.00583715, 52.9829189);
	#if (temporal_dither == 1)
		if ((abs(p0[2]) % 4) >= 2) pos.xy = float2(-pos.y, pos.x);
		if ((abs(p0[2]) % 2) >= 1) pos.x = -pos.x;

		float xy_magic = dot(pos.xy + qrand(p0[2]), magic.xy);
	#else
		float xy_magic = pos.x*magic.x + pos.y*magic.y;
	#endif

	float noise = (frac(magic.z*frac(xy_magic)) - 0.5)/colsteps;
	c0 += col_noise == 1 ? float3(-noise, noise, -noise) : noise;

	#if (quant_to_bit_depth == 1)
		return float4(round(c0*colsteps)/colsteps, alpha_out);
	#else
		return float4(c0, alpha_out);
	#endif
}