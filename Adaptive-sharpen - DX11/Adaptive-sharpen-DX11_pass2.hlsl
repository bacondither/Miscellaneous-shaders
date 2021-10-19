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

// Second pass, MUST BE PLACED IMMEDIATELY AFTER THE FIRST PASS IN THE CHAIN

// Adaptive sharpen - version DX11 - 2021-09-10
// Tuned for use post-resize, EXPECTS FULL RANGE GAMMA LIGHT (requires ps >= 4.0)

//======================================= Settings ================================================

#define curve_height    1.0                  // Main control of sharpening strength [>0]
                                             // 0.3 <-> 2.0 is a reasonable range of values
//-------------------------------------------------------------------------------------------------
#define video_level_out false                // True to preserve BTB & WTW (minor summation error)
                                             // Normally it should be set to false
//-------------------------------------------------------------------------------------------------
#define quality_mode    1                    // Use HQ original code path (set in both passes)
#define fskip           0                    // Skip limiting on flat areas where sharpdiff is low

//=================================================================================================
// Defined values under this row are "optimal" DO NOT CHANGE IF YOU DO NOT KNOW WHAT YOU ARE DOING!

#define curveslope      0.5                  // Sharpening curve slope, high edge values
//-------------------------------------------------------------------------------------------------
#define L_overshoot     0.003                // Max light overshoot before compression [>0.001]
#define L_compr_low     0.167                // Light compression, default (0.167=~6x)
#define L_compr_high    0.334                // Light compression, surrounded by edges (0.334=~3x)
//-------------------------------------------------------------------------------------------------
#define D_overshoot     0.009                // Max dark overshoot before compression [>0.001]
#define D_compr_low     0.250                // Dark compression, default (0.250=4x)
#define D_compr_high    0.500                // Dark compression, surrounded by edges (0.500=2x)
//-------------------------------------------------------------------------------------------------
#define scale_lim       0.1                  // Abs max change before compression [>0.01]
#define scale_cs        0.056                // Compression slope above scale_lim [0.0-1.0]
//-------------------------------------------------------------------------------------------------
#define dW_lothr        0.3                  // Start interpolating between W1 and W2
#define dW_hithr        0.8                  // When dW is equal to W2
//-------------------------------------------------------------------------------------------------
#define lowthr_mxw      0.1                  // Edge value for max lowthr weight [>0.01]
//-------------------------------------------------------------------------------------------------
#define pm_p            0.7                  // Power mean p-value [>0.0-1.0]
//-------------------------------------------------------------------------------------------------
#define alpha_out       1.0                  // MPDN requires the alpha channel output to be 1.0

//=================================================================================================
#define a_offset        2.0                  // Edge channel offset, MUST BE THE SAME IN ALL PASSES
#define bounds_check    true                 // If edge data is outside bounds, make pixels green
//=================================================================================================

Texture2D tex     : register(t0);
SamplerState samp : register(s0);

cbuffer PS_CONSTANTS : register(b0) { float2 pxy; };

// Soft if, fast linear approx
#define soft_if(a,b,c) ( saturate((a + b + c - 3*a_offset + 0.056)/(abs(maxedge) + 0.03) - 0.85) )

// Soft limit, modified tanh
#if (quality_mode == 0) // Tanh approx
	#define soft_lim(v,s)  ( saturate(abs(v/s)*(27 + sqr(v/s))/(27 + 9*sqr(v/s)))*s )
#else
	#define soft_lim(v,s)  ( (exp(2*min(abs(v), s*24)/s) - 1)/(exp(2*min(abs(v), s*24)/s) + 1)*s )
#endif

// Fast-skip threshold, keep max possible luma error under 0.5/2^bit-depth
#if (quality_mode == 0)
	// Approx of x = tanh(x/y)*y + 0.5/2^bit-depth, y = min(L_overshoot, D_overshoot)
	#define min_overshoot  ( min(abs(L_overshoot), abs(D_overshoot)) )
	//#define fskip_th       ( 0.114*pow(min_overshoot, 0.676) + 3.20e-4 ) // 10-bits
	#define fskip_th       ( 0.045*pow(min_overshoot, 0.667) + 1.75e-5 ) // 14-bits
#else
	// x = tanh(x/y)*y + 0.5/2^bit-depth, y = 0.0001
	#define fskip_th       ( 0.0000643723 ) // 16-bits
	//#define fskip_th       ( 0.000110882 ) // 14-bits
#endif

// Smoothstep to linearstep approx
//#define SStLS(a,b,x,c) ( clamp(-(6*(c - 1)*(b - x))/(5*(a - b)) - 0.1*c + 1.1, c, 1) )

// Weighted power mean
#define wpmean(a,b,w)  ( pow(w*pow(abs(a), pm_p) + abs(1-w)*pow(abs(b), pm_p), (1.0/pm_p)) )

// Get destination pixel values
#define get(x,y)       ( tex.Sample(samp, pxy*float2(x, y) + coord) )
#define satc(var)      ( float4(saturate((var).rgb), (var).a) )

#define max4(a,b,c,d)  ( max(max(a, b), max(c, d)) )
#define max3(a,b,c)    ( max(max(a, b), c) )
#define sqr(a)         ( (a)*(a) )

// Colour to luma, fast approx gamma, avg of rec. 709 & 601 luma coeffs
#define CtL(var)       ( sqrt(dot(float3(0.2558, 0.6511, 0.0931), saturate((var)*abs(var)).rgb)) )

// Center pixel diff
#define mdiff(a,b,c,d,e,f,g) ( abs(luma[g] - luma[a]) + abs(luma[g] - luma[b])       \
                             + abs(luma[g] - luma[c]) + abs(luma[g] - luma[d])       \
                             + 0.5*(abs(luma[g] - luma[e]) + abs(luma[g] - luma[f])) )

float4 main(float4 pos : SV_POSITION, float2 coord : TEXCOORD) : SV_Target
{
	float4 cO = get(0, 0);
	float c_edge = cO.a - a_offset;

	if (bounds_check == true)
	{
		if (c_edge > 16.0 || c_edge < -0.5) { return float4( 0, 1.0, 0, alpha_out ); }
	}

	// Get points, clip out of range colour data in c[0]
	// [                c22               ]
	// [           c24, c9,  c23          ]
	// [      c21, c1,  c2,  c3, c18      ]
	// [ c19, c10, c4,  c0,  c5, c11, c16 ]
	// [      c20, c6,  c7,  c8, c17      ]
	// [           c15, c12, c14          ]
	// [                c13               ]
	float4 c[25] = { satc( cO ), get(-1,-1), get( 0,-1), get( 1,-1), get(-1, 0),
	                 get( 1, 0), get(-1, 1), get( 0, 1), get( 1, 1), get( 0,-2),
	                 get(-2, 0), get( 2, 0), get( 0, 2), get( 0, 3), get( 1, 2),
	                 get(-1, 2), get( 3, 0), get( 2, 1), get( 2,-1), get(-3, 0),
	                 get(-2, 1), get(-2,-1), get( 0,-3), get( 1,-2), get(-1,-2) };

	// Allow for higher overshoot if the current edge pixel is surrounded by similar edge pixels
	float maxedge = max4( max4(c[1].a,c[2].a,c[3].a,c[4].a), max4(c[5].a,c[6].a,c[7].a,c[8].a),
	                      max4(c[9].a,c[10].a,c[11].a,c[12].a), c[0].a ) - a_offset;

	// [          x          ]
	// [       z, x, w       ]
	// [    z, z, x, w, w    ]
	// [ y, y, y, 0, y, y, y ]
	// [    w, w, x, z, z    ]
	// [       w, x, z       ]
	// [          x          ]
	float sbe = soft_if(c[2].a,c[9].a, c[22].a)*soft_if(c[7].a,c[12].a,c[13].a)  // x dir
	          + soft_if(c[4].a,c[10].a,c[19].a)*soft_if(c[5].a,c[11].a,c[16].a)  // y dir
	          + soft_if(c[1].a,c[24].a,c[21].a)*soft_if(c[8].a,c[14].a,c[17].a)  // z dir
	          + soft_if(c[3].a,c[23].a,c[18].a)*soft_if(c[6].a,c[20].a,c[15].a); // w dir

	#if (quality_mode == 0)
		float2 cs = lerp( float2(L_compr_low,  D_compr_low),
		                  float2(L_compr_high, D_compr_high), saturate(1.091*sbe - 2.282) );
	#else
		float2 cs = lerp( float2(L_compr_low,  D_compr_low),
		                  float2(L_compr_high, D_compr_high), smoothstep(2, 3.1, sbe) );
	#endif

	// RGB to luma
	float c0_Y = CtL(c[0]);

	float luma[25] = { c0_Y, CtL(c[1]), CtL(c[2]), CtL(c[3]), CtL(c[4]), CtL(c[5]), CtL(c[6]),
	                   CtL(c[7]),  CtL(c[8]),  CtL(c[9]),  CtL(c[10]), CtL(c[11]), CtL(c[12]),
	                   CtL(c[13]), CtL(c[14]), CtL(c[15]), CtL(c[16]), CtL(c[17]), CtL(c[18]),
	                   CtL(c[19]), CtL(c[20]), CtL(c[21]), CtL(c[22]), CtL(c[23]), CtL(c[24]) };

	// Pre-calculated default squared kernel weights
	const float3 W1 = float3(0.5,           1.0, 1.41421356237); // 0.25, 1.0, 2.0
	const float3 W2 = float3(0.86602540378, 1.0, 0.54772255751); // 0.75, 1.0, 0.3

	// Transition to a concave kernel if the center edge val is above thr
	#if (quality_mode == 0)
		float3 dW = sqr(lerp( W1, W2, saturate(2.4*c_edge - 0.82) ));
	#else
		float3 dW = sqr(lerp( W1, W2, smoothstep(0.3, 0.8, c_edge) ));
	#endif

	float mdiff_c0 = 0.02 + 3*( abs(luma[0]-luma[2]) + abs(luma[0]-luma[4])
	                          + abs(luma[0]-luma[5]) + abs(luma[0]-luma[7])
	                          + 0.25*(abs(luma[0]-luma[1]) + abs(luma[0]-luma[3])
	                                 +abs(luma[0]-luma[6]) + abs(luma[0]-luma[8])) );

	// Use lower weights for pixels in a more active area relative to center pixel area
	// This results in narrower and less visible overshoots around sharp edges
	float weights[12] = { ( min(mdiff_c0/mdiff(24, 21, 2,  4,  9,  10, 1),  dW.y) ),   // c1
	                      ( dW.x ),                                                    // c2
	                      ( min(mdiff_c0/mdiff(23, 18, 5,  2,  9,  11, 3),  dW.y) ),   // c3
	                      ( dW.x ),                                                    // c4
	                      ( dW.x ),                                                    // c5
	                      ( min(mdiff_c0/mdiff(4,  20, 15, 7,  10, 12, 6),  dW.y) ),   // c6
	                      ( dW.x ),                                                    // c7
	                      ( min(mdiff_c0/mdiff(5,  7,  17, 14, 12, 11, 8),  dW.y) ),   // c8
	                      ( min(mdiff_c0/mdiff(2,  24, 23, 22, 1,  3,  9),  dW.z) ),   // c9
	                      ( min(mdiff_c0/mdiff(20, 19, 21, 4,  1,  6,  10), dW.z) ),   // c10
	                      ( min(mdiff_c0/mdiff(17, 5,  18, 16, 3,  8,  11), dW.z) ),   // c11
	                      ( min(mdiff_c0/mdiff(13, 15, 7,  14, 6,  8,  12), dW.z) ) }; // c12

	weights[0] = (max3((weights[8]  + weights[9])/4,  weights[0], 0.25) + weights[0])/2;
	weights[2] = (max3((weights[8]  + weights[10])/4, weights[2], 0.25) + weights[2])/2;
	weights[5] = (max3((weights[9]  + weights[11])/4, weights[5], 0.25) + weights[5])/2;
	weights[7] = (max3((weights[10] + weights[11])/4, weights[7], 0.25) + weights[7])/2;

	// Calculate the negative part of the laplace kernel and the low threshold weight
	float lowthrsum   = 0;
	float weightsum   = 0;
	float neg_laplace = 0;

	[unroll] for (int pix = 0; pix < 12; ++pix)
	{
		#if (quality_mode == 0)
			float lowthr = clamp((13.2*c[pix + 1].a - a_offset - 0.221), 0.01, 1);

			neg_laplace += sqr(luma[pix + 1])*(abs(weights[pix])*lowthr);
		#else
			float t = saturate((c[pix + 1].a - a_offset - 0.01)/0.09);
			float lowthr = t*t*(2.97 - 1.98*t) + 0.01; // t*t*(3 - a*3 - (2 - a*2)*t) + a

			neg_laplace += pow(abs(luma[pix + 1]) + 0.06, 2.4)*(abs(weights[pix])*lowthr);
		#endif
		weightsum   += abs(weights[pix])*lowthr;
		lowthrsum   += lowthr/12;
	}

	#if (quality_mode == 0)
		neg_laplace = sqrt(neg_laplace/weightsum);
	#else
		neg_laplace = saturate(pow(neg_laplace/weightsum, (1.0/2.4)) - 0.06);
	#endif

	// Compute sharpening magnitude function
	float sharpen_val = curve_height/(curve_height*curveslope*pow(abs(c_edge), 3.5) + 0.625);

	// Calculate sharpening diff and scale
	float sharpdiff = (c0_Y - neg_laplace)*(lowthrsum*sharpen_val + 0.01);

#if (fskip == 1)
	[branch] if (abs(sharpdiff) > fskip_th)
	{
#endif
		// Calculate local near min & max, partial sort
		// Manually unrolled outer loop
		{
			float temp; int i; int ii;

			// 1st iteration
			[unroll] for (i = 0; i < 24; i += 2)
			{
				temp = luma[i];
				luma[i]   = min(luma[i], luma[i+1]);
				luma[i+1] = max(temp, luma[i+1]);
			}
			[unroll] for (ii = 24; ii > 0; ii -= 2)
			{
				temp = luma[0];
				luma[0]    = min(luma[0], luma[ii]);
				luma[ii]   = max(temp, luma[ii]);

				temp = luma[24];
				luma[24]   = max(luma[24], luma[ii-1]);
				luma[ii-1] = min(temp, luma[ii-1]);
			}

			// 2nd iteration
			[unroll] for (i = 1; i < 23; i += 2)
			{
				temp = luma[i];
				luma[i]   = min(luma[i], luma[i+1]);
				luma[i+1] = max(temp, luma[i+1]);
			}
			[unroll] for (ii = 23; ii > 1; ii -= 2)
			{
				temp = luma[1];
				luma[1]    = min(luma[1], luma[ii]);
				luma[ii]   = max(temp, luma[ii]);

				temp = luma[23];
				luma[23]   = max(luma[23], luma[ii-1]);
				luma[ii-1] = min(temp, luma[ii-1]);
			}

			#if (quality_mode != 0) // 3rd iteration
				[unroll] for (i = 2; i < 22; i += 2)
				{
					temp = luma[i];
					luma[i]   = min(luma[i], luma[i+1]);
					luma[i+1] = max(temp, luma[i+1]);
				}
				[unroll] for (ii = 22; ii > 2; ii -= 2)
				{
					temp = luma[2];
					luma[2]    = min(luma[2], luma[ii]);
					luma[ii]   = max(temp, luma[ii]);

					temp = luma[22];
					luma[22]   = max(luma[22], luma[ii-1]);
					luma[ii-1] = min(temp, luma[ii-1]);
				}
			#endif
		}

		// Calculate tanh scale factors
		#if (quality_mode == 0)
			float nmax = (max(luma[23], c0_Y)*2 + luma[24])/3;
			float nmin = (min(luma[1],  c0_Y)*2 + luma[0])/3;

			float min_dist  = min(abs(nmax - c0_Y), abs(c0_Y - nmin));
			float2 pn_scale = min_dist + float2(L_overshoot, D_overshoot);
		#else
			float nmax = (max(luma[22] + luma[23]*2, c0_Y*3) + luma[24])/4;
			float nmin = (min(luma[2]  + luma[1]*2,  c0_Y*3) + luma[0])/4;

			float min_dist  = min(abs(nmax - c0_Y), abs(c0_Y - nmin));
			float2 pn_scale = float2( min(L_overshoot + min_dist, 1.0001 - c0_Y),
			                          min(D_overshoot + min_dist, 0.0001 + c0_Y) );
		#endif

		pn_scale = min(pn_scale, scale_lim*(1 - scale_cs) + pn_scale*scale_cs);

		// Soft limited anti-ringing with tanh, wpmean to control compression slope
		sharpdiff = wpmean( max(sharpdiff, 0), soft_lim( max(sharpdiff, 0), pn_scale.x ), cs.x )
		          - wpmean( min(sharpdiff, 0), soft_lim( min(sharpdiff, 0), pn_scale.y ), cs.y );
#if (fskip == 1)
	}
#endif

	// Compensate for saturation loss/gain while making pixels brighter/darker
	float sharpdiff_lim = saturate(c0_Y + sharpdiff) - c0_Y;
	float satmul = (c0_Y + max(sharpdiff_lim*0.9, sharpdiff_lim)*1.03 + 0.03)/(c0_Y + 0.03);
	float3 res = c0_Y + (sharpdiff_lim*3 + sharpdiff)/4 + (c[0].rgb - c0_Y)*satmul;

	return float4( (video_level_out == true ? res + cO.rgb - c[0].rgb : res), alpha_out );
}