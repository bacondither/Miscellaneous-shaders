// $MinimumShaderProfile: ps_3_0

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

// Adaptive sharpen - version LQ-1Pass - 2021-10-17
// Lower quality one pass version, similiar speed to the two pass version
// Tuned for use post-resize, EXPECTS FULL RANGE GAMMA LIGHT (requires ps >= 3.0)

//======================================= Settings ================================================

#define curve_height    1.0                  // Main control of sharpening strength [>0]
                                             // 0.3 <-> 2.0 is a reasonable range of values
//-------------------------------------------------------------------------------------------------
#define video_level_out 0                    // 1 to preserve BTB & WTW (minor summation error)
                                             // Normally it should be set to 0
//-------------------------------------------------------------------------------------------------
#define hq_e0           1                    // HQ centre edge calc used in the two pass version

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
#define pm_p            0.7                  // Power mean p-value [>0.0-1.0]
//-------------------------------------------------------------------------------------------------
#define alpha_out       1.0                  // MPDN requires the alpha channel output to be 1.0
                                             // Can be set to 0.0 for MPC-HC

//=================================================================================================

sampler s0 : register(s0);
float2 p1  : register(c1);

// Helper funcs
#define sqr(a)         ( (a)*(a) )
#define max4(a,b,c,d)  ( max(max(a, b), max(c, d)) )
#define max3(a,b,c)    ( max(max(a, b), c) )

// Soft if, fast linear approx
#define soft_if(a,b,c) ( saturate((a + b + c + 0.056/2.3)/(maxedge + 0.03/2.3) - 0.85) )

// Soft limit, modified tanh approx
#define soft_lim(v,s)  ( saturate(abs(v/s)*(27 + sqr(v/s))/(27 + 9*sqr(v/s)))*s )

// Weighted power mean
#define wpmean(a,b,w)  ( pow(w*pow(abs(a), pm_p) + abs(1-w)*pow(abs(b), pm_p), (1.0/pm_p)) )

// Component-wise distance
#define b_diff(pix)    ( abs(blur - c[pix]) )

// Get destination pixel values
#define get(x,y)       ( saturate(tex2D(s0, p1*float2(x, y) + tex).rgb) )
#define dxdy(val)      ( length(abs(ddx(val)) + abs(ddy(val))) ) // =~1/2.3 hq edge without c_comp

// Colour to luma, fast approx gamma, avg of rec. 709 & 601 luma coeffs
#define CtL(RGB)       ( sqrt(dot(sqr(RGB), float3(0.2558, 0.6511, 0.0931))) )

// Smoothstep to linearstep approx
//#define SStLS(a,b,x,c) ( clamp(-(6*(c - 1)*(b - x))/(5*(a - b)) - 0.1*c + 1.1, c, 1) )

float4 main(float2 tex : TEXCOORD0) : COLOR
{
	// Get points, clip out of range colour data
	// [                c22               ]
	// [           c24, c9,  c23          ]
	// [      c21, c1,  c2,  c3, c18      ]
	// [ c19, c10, c4,  c0,  c5, c11, c16 ]
	// [      c20, c6,  c7,  c8, c17      ]
	// [           c15, c12, c14          ]
	// [                c13               ]
	float3 c[25] = { get( 0, 0), get(-1,-1), get( 0,-1), get( 1,-1), get(-1, 0),
	                 get( 1, 0), get(-1, 1), get( 0, 1), get( 1, 1), get( 0,-2),
	                 get(-2, 0), get( 2, 0), get( 0, 2), get( 0, 3), get( 1, 2),
	                 get(-1, 2), get( 3, 0), get( 2, 1), get( 2,-1), get(-3, 0),
	                 get(-2, 1), get(-2,-1), get( 0,-3), get( 1,-2), get(-1,-2) };

	float e[25] = { dxdy(c[0]),  dxdy(c[1]),  dxdy(c[2]),  dxdy(c[3]),  dxdy(c[4]),
	                dxdy(c[5]),  dxdy(c[6]),  dxdy(c[7]),  dxdy(c[8]),  dxdy(c[9]),
	                dxdy(c[10]), dxdy(c[11]), dxdy(c[12]), dxdy(c[13]), dxdy(c[14]),
	                dxdy(c[15]), dxdy(c[16]), dxdy(c[17]), dxdy(c[18]), dxdy(c[19]),
	                dxdy(c[20]), dxdy(c[21]), dxdy(c[22]), dxdy(c[23]), dxdy(c[24]) };

	// Gauss blur 3x3
	float3 blur = (2*(c[2]+c[4]+c[5]+c[7]) + (c[1]+c[3]+c[6]+c[8]) + 4*c[0])/16;

	// Contrast compression, center = 0.5, scaled to 1/3
	float c_comp = saturate(4.0/15.0 + 0.9*exp2(dot(blur, -37.0/15.0)));

	#if (hq_e0 == 1)
		// Edge detection
		// Relative matrix weights
		// [          1          ]
		// [      4,  5,  4      ]
		// [  1,  5,  6,  5,  1  ]
		// [      4,  5,  4      ]
		// [          1          ]
		float3 edge = 1.38*(b_diff(0))
		            + 1.15*(b_diff(2) + b_diff(4)  + b_diff(5)  + b_diff(7))
		            + 0.92*(b_diff(1) + b_diff(3)  + b_diff(6)  + b_diff(8))
		            + 0.23*(b_diff(9) + b_diff(10) + b_diff(11) + b_diff(12));

		float cedge = length(edge)*c_comp;
	#else
		float cedge = e[0]*4.5*c_comp;
	#endif

	// Allow for higher overshoot if the current edge pixel is surrounded by similar edge pixels
	float maxedge = max4( max4(e[1],e[2],e[3],e[4]), max4(e[5],e[6],e[7],e[8]),
	                      max4(e[9],e[10],e[11],e[12]), e[0] );

	// [          x          ]
	// [       z, x, w       ]
	// [    z, z, x, w, w    ]
	// [ y, y, y, 0, y, y, y ]
	// [    w, w, x, z, z    ]
	// [       w, x, z       ]
	// [          x          ]
	float sbe = soft_if(e[2],e[9], e[22])*soft_if(e[7],e[12],e[13])  // x dir
	          + soft_if(e[4],e[10],e[19])*soft_if(e[5],e[11],e[16])  // y dir
	          + soft_if(e[1],e[24],e[21])*soft_if(e[8],e[14],e[17])  // z dir
	          + soft_if(e[3],e[23],e[18])*soft_if(e[6],e[20],e[15]); // w dir

	float2 cs = lerp( float2(L_compr_low,  D_compr_low),
	                  float2(L_compr_high, D_compr_high), saturate(2.4002*sbe - 2.282) );

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
	float3 dW = sqr(lerp( W1, W2, saturate(2.4*cedge - 0.82) ));

	// Use lower weights for pixels in a more active area relative to center pixel area
	// This results in narrower and less visible overshoots around sharp edges
	float modif_e0 = 3*e[0] + 0.02/2.3;

	float weights[12] = { ( min(modif_e0/e[1],  dW.y) ),   // c1
	                      ( dW.x ),                        // c2
	                      ( min(modif_e0/e[3],  dW.y) ),   // c3
	                      ( dW.x ),                        // c4
	                      ( dW.x ),                        // c5
	                      ( min(modif_e0/e[6],  dW.y) ),   // c6
	                      ( dW.x ),                        // c7
	                      ( min(modif_e0/e[8],  dW.y) ),   // c8
	                      ( min(modif_e0/e[9],  dW.z) ),   // c9
	                      ( min(modif_e0/e[10], dW.z) ),   // c10
	                      ( min(modif_e0/e[11], dW.z) ),   // c11
	                      ( min(modif_e0/e[12], dW.z) ) }; // c12

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
		float lowthr = clamp((13.2*2.3*e[pix + 1] - 0.221), 0.01, 1); // lowthr_mxw = 0.1

		neg_laplace += sqr(luma[pix + 1])*(abs(weights[pix])*lowthr);
		weightsum   += abs(weights[pix])*lowthr;
		lowthrsum   += lowthr/12;
	}

	neg_laplace = sqrt(neg_laplace/weightsum);

	// Compute sharpening magnitude function
	float sharpen_val = curve_height/(curve_height*curveslope*pow(abs(cedge), 3.5) + 0.625);

	// Calculate sharpening diff and scale
	float sharpdiff = (c0_Y - neg_laplace)*(lowthrsum*sharpen_val + 0.01);

	// Calculate local near min & max, partial sort
	[unroll] for (int i = 0; i < 2; ++i)
	{
		float temp;

		[unroll] for (int j = i; j < 24-i; j += 2)
		{
			temp = luma[j];
			luma[j]   = min(luma[j], luma[j+1]);
			luma[j+1] = max(temp, luma[j+1]);
		}

		[unroll] for (int jj = 24-i; jj > i; jj -= 2)
		{
			temp = luma[i];
			luma[i]    = min(luma[i], luma[jj]);
			luma[jj]   = max(temp, luma[jj]);

			temp = luma[24-i];
			luma[24-i] = max(luma[24-i], luma[jj-1]);
			luma[jj-1] = min(temp, luma[jj-1]);
		}
	}

	float nmax = (max(luma[23], c0_Y)*2 + luma[24])/3;
	float nmin = (min(luma[1],  c0_Y)*2 + luma[0])/3;

	float min_dist  = min(abs(nmax - c0_Y), abs(c0_Y - nmin));
	float2 pn_scale = float2(L_overshoot, D_overshoot) + min_dist;

	pn_scale = min(pn_scale, scale_lim*(1 - scale_cs) + pn_scale*scale_cs);

	// Soft limited anti-ringing with tanh, wpmean to control compression slope
	sharpdiff = wpmean( max(sharpdiff, 0), soft_lim( max(sharpdiff, 0), pn_scale.x ), cs.x )
	          - wpmean( min(sharpdiff, 0), soft_lim( min(sharpdiff, 0), pn_scale.y ), cs.y );

	// Compensate for saturation loss/gain while making pixels brighter/darker
	float sharpdiff_lim = saturate(c0_Y + sharpdiff) - c0_Y;
	float satmul = (c0_Y + max(sharpdiff_lim*0.9, sharpdiff_lim)*1.03 + 0.03)/(c0_Y + 0.03);
	float3 res = c0_Y + (sharpdiff_lim*3 + sharpdiff)/4 + (c[0] - c0_Y)*satmul;

	return float4( (video_level_out == 1 ? res + tex2D(s0, tex).rgb - c[0] : res), alpha_out );
}