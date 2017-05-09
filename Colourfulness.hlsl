// $MinimumShaderProfile: ps_2_b

// Copyright (c) 2016-2017, bacondither
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

// Colourfulness - version 2017-05-01 - (requires ps >= ps_2_b)
// EXPECTS FULL RANGE GAMMA LIGHT

sampler s0 : register(s0);
float2 p1  : register(c1);

//--------------------------------- Settings ------------------------------------------------

#define colourfulness  0.4          // Degree of colourfulness, 0 = neutral [-1.0<->2.0]
#define lim_luma       0.7          // Lower vals allow more change near clipping [0.1<->1.0]

#define alpha_out      1.0          // MPDN requires alpha channel output to be 1.0

#define fast_luma      0            // Rapid approx of sRGB gamma, small difference in quality

//-------------------------------------------------------------------------------------------

// Sigmoid function, sign(v)*pow(pow(abs(v), -2) + pow(s, -2), 1.0/-2)
#define soft_lim(v,s)  ( (v*s)*rcp(sqrt(s*s + v*v)) )

// Weighted power mean, p = 0.5
#define wpmean(a,b,w)  ( pow(w*sqrt(abs(a)) + abs(1-w)*sqrt(abs(b)), 2) )

// Max/Min RGB components
#define max3(RGB)      ( max((RGB).r, max((RGB).g, (RGB).b)) )
#define min3(RGB)      ( min((RGB).r, min((RGB).g, (RGB).b)) )

// Mean of Rec. 709 & 601 luma coefficients
#define lumacoeff        float3(0.2558, 0.6511, 0.0931)

float4 main(float2 tex : TEXCOORD0) : COLOR
{
	#if (fast_luma == 1)
		float3 c0  = tex2D(s0, tex).rgb;
		float luma = sqrt(dot(saturate(c0*abs(c0)), lumacoeff));
		c0 = saturate(c0);
	#else // Better approx of sRGB gamma
		float3 c0  = saturate(tex2D(s0, tex).rgb);
		float luma = pow(dot(pow(c0 + 0.06, 2.4), lumacoeff), 1.0/2.4) - 0.06;
	#endif

	// Calc colour saturation change
	float3 diff_luma = c0 - luma;
	float3 c_diff = diff_luma*(colourfulness + 1) - diff_luma;

	if (colourfulness > 0.0)
	{
		// 120% of c_diff clamped to max visible range + overshoot
		float3 rlc_diff = clamp((c_diff*1.2) + c0, -0.0001, 1.0001) - c0;

		// Calc max saturation-increase without altering RGB ratios
		float poslim = (1.0002 - luma)/(abs(max3(diff_luma)) + 0.0001);
		float neglim = (luma + 0.0002)/(abs(min3(diff_luma)) + 0.0001);

		float3 diffmax = diff_luma*min(min(poslim, neglim), 32) - diff_luma;

		// Soft limit diff
		c_diff = soft_lim( c_diff, max(wpmean(diffmax, rlc_diff, lim_luma), 1e-6) );
	}

	return float4(c0 + c_diff, alpha_out);
}