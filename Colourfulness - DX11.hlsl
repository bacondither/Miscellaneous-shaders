// $MinimumShaderProfile: ps_4_0

// Copyright (c) 2016-2021, bacondither
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

// Colourfulness - version DX11 - 2021-09-01 - (requires ps >= 4.0)
// EXPECTS FULL RANGE GAMMA LIGHT

//================================= Settings ======================================================

#define colourfulness  0.4          // Degree of colourfulness, 0 = neutral [-1.0<->2.0]
#define lim_luma       0.7          // Lower vals allows for more change near clipping [0.1<->1.0]
//-------------------------------------------------------------------------------------------------
#define alpha_out      1.0          // MPDN requires alpha channel output to be 1.0
//-------------------------------------------------------------------------------------------------
#define fast_luma      0            // Rapid approx of sRGB gamma, small difference in quality

//=================================================================================================

Texture2D tex     : register(t0);
SamplerState samp : register(s0);

// Sigmoid function, sign(v)*pow(pow(abs(v), -2) + pow(s, -2), 1.0/-2)
#define soft_lim(v,s)  ( (v*s)*rcp(sqrt(s*s + v*v)) )

// Weighted power mean, p = 0.5
#define wpmean(a,b,w)  ( pow(w*sqrt(abs(a)) + abs(1-w)*sqrt(abs(b)), 2) )

// Max/Min RGB components
#define maxRGB(c)      ( max((c).r, max((c).g, (c).b)) )
#define minRGB(c)      ( min((c).r, min((c).g, (c).b)) )

// Mean of Rec. 709 & 601 luma coefficients
#define lumacoeff        float3(0.2558, 0.6511, 0.0931)


float4 main(float4 pos : SV_POSITION, float2 coord : TEXCOORD) : SV_Target
{
	#if (fast_luma == 1)
		float3 c0  = tex.Sample(samp, coord).rgb;
		float luma = sqrt(dot(saturate(c0*abs(c0)), lumacoeff));
		c0 = saturate(c0);
	#else // Better approx of sRGB gamma
		float3 c0  = saturate(tex.Sample(samp, coord).rgb);
		float luma = saturate(pow(dot(pow(c0 + 0.06, 2.4), lumacoeff), 1.0/2.4) - 0.06);
	#endif

	// Calc colour saturation change
	float3 diff_luma = c0 - luma;
	float3 c_diff = diff_luma*colourfulness;

	if (colourfulness > 0.0)
	{
		// c_diff*fudge factor, clamped to max visible range + overshoot
		float3 rlc_diff = clamp((c_diff*1.2) + c0, -0.0001, 1.0001) - c0;

		// Calc max saturation-increase without altering RGB ratios
		float poslim = (1.0002 - luma)/(abs(maxRGB(diff_luma)) + 0.0001);
		float neglim = (luma + 0.0002)/(abs(minRGB(diff_luma)) + 0.0001);

		float3 diffmax = diff_luma*min(min(poslim, neglim), 32) - diff_luma;

		// Soft limit saturation diff
		c_diff = soft_lim( c_diff, max(wpmean(diffmax, rlc_diff, lim_luma), 1e-7) );
	}

	return float4(c0 + c_diff, alpha_out);
}