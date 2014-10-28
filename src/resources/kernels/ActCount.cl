//#pragma OPENCL EXTENSION cl_khr_3d_image_writes : enable

#define MAXF 1
#define MAXDPHIDT 2

__constant sampler_t def_sampler = CLK_NORMALIZED_COORDS_FALSE |
								CLK_ADDRESS_CLAMP_TO_EDGE |
								CLK_FILTER_NEAREST;

__constant float thresporc = .004f;
__constant float EPS = .00001f;

float temp_dD(float a, float b, float c, float d, float e, float f, float phi){

	float ap = a < 0? 0: a;
	float bp = b < 0? 0: b;
	float cp = c < 0? 0: c;
	float dp = d < 0? 0: d;
	float ep = e < 0? 0: e;
	float fp = f < 0? 0: f;

	float an = a > 0? 0: a;
	float bn = b > 0? 0: b;
	float cn = c > 0? 0: c;
	float dn = d > 0? 0: d;
	float en = e > 0? 0: e;
	float fn = f > 0? 0: f;

	float dD = 0;
	if( phi > 0){
		dD = sqrt( max( pow(ap,2), pow(bn,2) ) + 
				   max( pow(cp,2), pow(dn,2) ) +
				   max( pow(ep,2), pow(fn,2) ) ) -1;
	}
	if( phi < 0){
		dD = sqrt( max( pow(an,2), pow(bp,2) ) + 
				   max( pow(cn,2), pow(dp,2) ) +
				   max( pow(en,2), pow(fp,2) ) ) -1;
	}
	return dD;
}

// It computes the curvature of the curve phi close to 0 and
// also the value of the Force F
__kernel void
smoothPhi(global float* phi, global float* sm_phi, float dt, int width, int height, int depth){

    int globId = (int)get_global_id(0);// From 0 to height*depth

	//Obtain current index
	int slice = width*height;//This is the size of one 'slice'
	int row = width;//This is the size of one 'slice'

	// This is the case we are in the middle of the cube, no worries about the
	// boundaries
	int curr = globId*width;//Current value

	// First 8 neighbors same slice
	int lf = curr-1;//The value left  (left)
	int ri = curr+1;//The value right (right) 
	int dn = curr+row;if( (curr+row) % slice == 0){ dn = curr; }//down value (test if is last row)
	int dr = dn+1;// (down right)
	int dl = dn-1;// (down left)
	int up = curr-row; if(curr % slice == 0){ up = curr; }//up value (test if is first row)
	int ur = up+1;// (up right)
	int ul = up-1;// (up left)
	// Farther 9 neighbors

	// ----------------- If we are are in the last slice then we can't have a far slice
	if( curr > (slice*depth-1) ){ slice = 0;}

	int fcurr = curr + slice;//(far current) 
	int flf = fcurr-1;// (far left)
	int fri = fcurr+1;//(far right) 
	int fdn = fcurr+row; if( (curr+row) % slice == 0){ fdn = fcurr; }//far down value (test if is last row
	int fdr = fdn+1;// (far down right)
	int fdl = fdn-1;// (far down left)
	int fup = curr-row; if(curr % slice == 0){ fup = fcurr; }//The value above (up)
	int fur = up+1;// (up right)
	int ful = up-1;// (up left)
	
	// ----------------- If we are are in the first slice then we can't have a closer slice
	slice = width*height;
	if( curr < slice ){ slice = 0;}

	// Closer 9 neighbors
	int ccurr = curr - slice;//(closer current) 
	int clf = ccurr-1;// (closer left)
	int cri = ccurr+1;//(closer right) 
	int cdn = ccurr+row; if( (curr+row) % slice == 0){ cdn = ccurr; }//far down value (test if is last row
	int cdr = cdn+1;// (closer down right)
	int cdl = cdn-1;// (closer down left)
	int cup = ccurr-row; if(curr % slice == 0){ cup = ccurr; }//The value above (up)
	int cur = cup+1;// (closer up right)
	int cul = cup-1;// (closer up left)

	//------------ First column ---------
	float a = 0; // Backward in x
	float b = phi[ri] - phi[curr]; // Forward in x
	float c = phi[curr] - phi[dn]; // Backward in y
	float d = phi[up] - phi[curr]; //Forward in y
	float e = phi[curr] - phi[ccurr]; // Backward in z
	float f = phi[fcurr] - phi[curr]; // Forward in z

	float dD = temp_dD(a,b,c,d,e,f,phi[curr]);
 	sm_phi[curr] = phi[curr] - dt * (phi[curr]/sqrt( pow(phi[curr],2) + 1)) * dD;
	//Iterate over the 'middle' columns
	for(int col = 1; col < width-1; col++){
		a = phi[curr+col] - phi[lf+col]; // Backward in x
		b = phi[ri+col] - phi[curr+col]; // Forward in x
		c = phi[curr+col] - phi[dn+col]; // Backward in y
		d = phi[up+col] - phi[curr+col]; //Forward in y
		e = phi[curr+col] - phi[ccurr+col]; // Backward in z
		f = phi[fcurr+col] - phi[curr+col]; // Forward in z

		dD = temp_dD(a,b,c,d,e,f,phi[curr+col]);
		sm_phi[curr+col] = phi[curr+col] - dt * (phi[curr+col]/sqrt( pow(phi[curr+col],2) + 1)) * dD;
	}

	a = phi[curr] - phi[lf]; // Backward in x
	b = 0; // Forward in x
	c = phi[curr] - phi[dn]; // Backward in y
	d = phi[up] - phi[curr]; //Forward in y
	e = phi[curr] - phi[ccurr]; // Backward in z
	f = phi[fcurr] - phi[curr]; // Forward in z

	dD = temp_dD(a,b,c,d,e,f,phi[curr]);
	int col = width-1;
	sm_phi[curr+col] = phi[curr+col] - dt * (phi[curr+col]/sqrt( pow(phi[curr+col],2) + 1)) * dD;
}

__kernel
void newphi( __global float* phi, __global float* dphidt,
			__global float* max_dphidt, int width, int height){
				
	float dt = .45/(max_dphidt[0] + EPS);
    int globId = (int)get_global_id(0);// From 0 to height*depth
	int curr = globId*width;//Current value

	//Iterate over the 'middle' columns
	for(int col = 0; col < width; col++){
		phi[curr+col] = phi[curr+col] + dt*dphidt[curr+col];
	}
}

__kernel
void reduce(__global float* buffer,
            __local float* scratch,
			__global float* result,
            __const int length,
			__const int absVal) {
	
	int global_index = get_global_id(0);
	float maxVal = 0;
	// Loop sequentially over chunks of input vector
	while (global_index < length) {
		float element = buffer[global_index];
		maxVal = (maxVal > element) ? maxVal : element;
		global_index += get_global_size(0);
	}

	// Perform parallel reduction
	int local_index = get_local_id(0);
	scratch[local_index] = maxVal;
	barrier(CLK_LOCAL_MEM_FENCE);

	for(int offset = get_local_size(0) / 2; offset > 0; offset = offset / 2) {
		if (local_index < offset) {
			float other = scratch[local_index + offset];
			float mine = scratch[local_index];
			scratch[local_index] = (mine > other) ? mine : other;
		}
		barrier(CLK_LOCAL_MEM_FENCE);
	}
	if (local_index == 0) {
		result[get_group_id(0)] = scratch[0];
	}
}


__kernel void
dphidt(__global float* curvature, __global float* F,
		__global float* max_F, __global float* dphidt, float alpha, int width, int height){

    int globId = (int)get_global_id(0);// From 0 to height*depth
	int curr = globId*width;//Current value

	float maxF = max_F[0];//Max value of F

	//Iterate over the 'middle' columns
	for(int col = 0; col < width; col++){
		dphidt[curr+col] = (F[curr+col]/(maxF + EPS)) + alpha*curvature[curr+col];
	}

}

/**
* Computes the energy force of the Active Contour. It is divided one
* thread per 'row', so there height*depth total threads. 
*/
__kernel void
compF(global float* avg_in_out, global float* I, 
			global float* F, int width, int height, int depth){

    int globId = (int)get_global_id(0);// From 0 to height*depth

	// This is the case we are in the middle of the cube, no worries about the
	// boundaries
	int curr = globId*width;//Current value

	// ----------------- If we are are in the last slice then we can't have a far slice
	float u = avg_in_out[0];
	float v = avg_in_out[1];

	//Iterate over the 'middle' columns
	for(int col = 0; col < width; col++){
		F[curr+col] = pow( (I[curr+col] - u), 2) - pow( (I[curr+col] - v), 2);
//		F[curr+col] = curr+col;
	}

}//compF



// It computes the curvature of the curve phi. Each thread is in charge of
// evaluating a 'row' of elements. 
__kernel void
curvature(global float* phi, global float* curvature, 
			int width, int height, int depth){

    int globId = (int)get_global_id(0);// From 0 to height*depth

	//Obtain current index
	int slice = width*height;//This is the size of one 'slice'
	int row = width;//This is the size of one 'slice'

	// This is the case we are in the middle of the cube, no worries about the
	// boundaries
	int curr = globId*width;//Current value

	// First 8 neighbors same slice
	int lf = curr-1;//The value left  (left)
	int ri = curr+1;//The value right (right) 
	int dn = curr+row;if( (curr+row) % slice == 0){ dn = curr; }//down value (test if is last row)
	int dr = dn+1;// (down right)
	int dl = dn-1;// (down left)
	int up = curr-row; if(curr % slice == 0){ up = curr; }//up value (test if is first row)
	int ur = up+1;// (up right)
	int ul = up-1;// (up left)
	// Farther 9 neighbors

	// ----------------- If we are are in the last slice then we can't have a far slice
	if( curr > (slice*depth-1) ){ slice = 0;}

	int fcurr = curr + slice;//(far current) 
	int flf = fcurr-1;// (far left)
	int fri = fcurr+1;//(far right) 
	int fdn = fcurr+row; if( (curr+row) % slice == 0){ fdn = fcurr; }//far down value (test if is last row
	int fdr = fdn+1;// (far down right)
	int fdl = fdn-1;// (far down left)
	int fup = curr-row; if(curr % slice == 0){ fup = fcurr; }//The value above (up)
	int fur = up+1;// (up right)
	int ful = up-1;// (up left)
	
	// ----------------- If we are are in the first slice then we can't have a closer slice
	slice = width*height;
	if( curr < slice ){ slice = 0;}

	// Closer 9 neighbors
	int ccurr = curr - slice;//(closer current) 
	int clf = ccurr-1;// (closer left)
	int cri = ccurr+1;//(closer right) 
	int cdn = ccurr+row; if( (curr+row) % slice == 0){ cdn = ccurr; }//far down value (test if is last row
	int cdr = cdn+1;// (closer down right)
	int cdl = cdn-1;// (closer down left)
	int cup = ccurr-row; if(curr % slice == 0){ cup = ccurr; }//The value above (up)
	int cur = cup+1;// (closer up right)
	int cul = cup-1;// (closer up left)

	//First order
	float phi_x = 0;
	float phi_y = 0;
	float phi_z = 0;
	//Second order
	float phi_xx = 0;
	float phi_yy = 0;
	float phi_zz = 0;
	float phi_xy = 0;
	float phi_xz = 0;
	float phi_zy = 0;
	//Squares
	float phi_x2 = 0;
	float phi_y2 = 0;
	float phi_z2 = 0;

	//------------ First column ---------
	phi_x = phi[ri] - phi[curr];
	phi_y = phi[up] - phi[dn];
	phi_z = phi[fcurr] - phi[ccurr];
	//Second order
	phi_xx = phi[curr] - 2*phi[curr] + phi[ri];
	phi_yy = phi[up] - 2*phi[curr] + phi[dn];
	phi_zz = phi[fcurr] - 2*phi[curr] + phi[ccurr];;
	phi_xy = -0.25*phi[dr] - 0.25*phi[ur] + .25*phi[dn] + .25*phi[up];
//		phi_xz = 0;
//		phi_zy = 0;
	//Squares
	phi_x2 = phi_x*phi_x;
	phi_y2 = phi_y*phi_y;
	phi_z2 = phi_z*phi_z;

	curvature[curr] =   ( phi_x2*phi_yy + phi_x2*phi_zz + phi_y2*phi_zz + 
					phi_z2*phi_xx + phi_z2*phi_yy - 2*phi_x*phi_y*phi_xy + 
					-2*phi_x*phi_z*phi_xz - 2*phi_y*phi_z*phi_zy) / 
					pow((float)(phi_x2 + phi_y2 + phi_z2 + .001),(float)(3/2));

	//Iterate over the 'middle' columns
	for(int col = 1; col < width-1; col++){
		//First order
		phi_x = phi[ri+col] - phi[lf+col];
		phi_y = phi[up+col] - phi[dn+col];
		phi_z = phi[fcurr+col] - phi[ccurr+col];
		//Second order
		phi_xx = phi[lf+col] - 2*phi[curr] + phi[ri+col];
		phi_yy = phi[up+col] - 2*phi[curr] + phi[dn+col];
		phi_zz = phi[fcurr+col] - 2*phi[curr] + phi[ccurr+col];;
		phi_xy = -0.25*phi[dr+col] - 0.25*phi[ur+col] + .25*phi[dl+col] + .25*phi[ul+col];
//		phi_xz = 0;
//		phi_zy = 0;
		//Squares
		phi_x2 = phi_x*phi_x;
		phi_y2 = phi_y*phi_y;
		phi_z2 = phi_z*phi_z;

		curvature[curr+col] = ( phi_x2*phi_yy + phi_x2*phi_zz + phi_y2*phi_zz + 
					phi_z2*phi_xx + phi_z2*phi_yy - 2*phi_x*phi_y*phi_xy + 
					-2*phi_x*phi_z*phi_xz - 2*phi_y*phi_z*phi_zy) / 
					pow((float)(phi_x2 + phi_y2 + phi_z2 + .001),(float)(3/2));

//		curvature[globId] = currCoords.x;
		//	curvature[globId] = globId*width;
	}

	//-------------------- Last column ----------------
	int col = width-1;
	//First order
	phi_x = phi[curr+col] - phi[lf+col];
	phi_y = phi[up+col] - phi[dn+col];
	phi_z = phi[fcurr+col] - phi[ccurr+col];
	//Second order
	phi_xx = phi[lf+col] - 2*phi[curr] + phi[curr+col];
	phi_yy = phi[up+col] - 2*phi[curr] + phi[dn+col];
	phi_zz = phi[fcurr+col] - 2*phi[curr] + phi[ccurr+col];;
	phi_xy = -0.25*phi[dn+col] - 0.25*phi[up+col] + .25*phi[dl+col] + .25*phi[ul+col];
//		phi_xz = 0;
//		phi_zy = 0;
	//Squares
	phi_x2 = phi_x*phi_x;
	phi_y2 = phi_y*phi_y;
	phi_z2 = phi_z*phi_z;

	curvature[curr+col] = ( phi_x2*phi_yy + phi_x2*phi_zz + phi_y2*phi_zz + 
				phi_z2*phi_xx + phi_z2*phi_yy - 2*phi_x*phi_y*phi_xy + 
				-2*phi_x*phi_z*phi_xz - 2*phi_y*phi_z*phi_zy) / 
				pow((float)(phi_x2 + phi_y2 + phi_z2 + .001),(float)(3/2));

}//curvature

int indxFromCoordAC(int width, int height, int row, int col, int dim){
    return width*row*dim + dim*col;
}

int indxFromCoord3D(int width, int height, int depth,
							int row, int col, int z, int dim){
    return width*height*z + width*row + col;
}

/**
* Copies a 3D image into a buffer. 
* The image should only contain one band.
*/
__kernel void textToBufNew(write_only image3d_t in, global float* buf){

	int width = get_image_width(in);
	int height = get_image_height(in);
	int depth = get_image_depth(in);

	int w_by_h = width*height;
    int idx = (int)get_global_id(0);

	int z = (int)(idx/w_by_h);
	int prevCube  = (z-1)*w_by_h;

	int row = (int)((idx - prevCube)/width);
	int col = idx - prevCube - (row-1)*width ;

	//write_imagef(in,def_sampler, (int4)(col,row,z,1));
}

__kernel void textToBuf(read_only image3d_t in, global float* buf){
	int width = get_image_width(in);
	int height = get_image_height(in);
	int depth = get_image_depth(in);

    int oneDidx= (int)get_global_id(0);

/*
	int size = width*height*depth;
	int z = ceil(oneDidx/(width*height));//Which depth are we
	int col = (int) 
	int row = 

	float4 textVal = read_imagef(in, def_sampler, (int4)(col,row,z,1));

	buf[oneDidx] = textVal.x; 
*/
}

/**
 * This kernel copies one buffer into an image. 
 * If 'allBands' is true, then the buffer should contain the 4 bands on it.
 * If 'allBands' is false, then the buffer should contain only information
 * in one channel, and it is copied into the 3 channels RGB of the image
*/
__kernel void bufToText(global float* buf, write_only image2d_t out, 
					int width, int height, int allBands){

    int col = (int)get_global_id(0);
    int row = (int)get_global_id(1);

	int currIndx = indxFromCoordAC(width, height, row, col, 1);

	float4 textVal;
	if(allBands){
		float red = buf[currIndx*4];
		float green = buf[currIndx*4 + 1];
		float blue = buf[currIndx*4 + 2];
		float alpha = buf[currIndx*4 + 3];

		textVal = (float4)(red, green, blue, alpha);
	}else{
		float val = buf[currIndx];
		textVal = (float4)(val, val, val, 1);
	}

	write_imagef(out, (int2)(col,row), textVal);
}

/**
	* This kernel computes local averages of pixels inside and outside the object
	* for every warp size. It only works for positive values 
* How we are doing it is as follows:
* Each group of will process (LocalMemSize / width) lines each time.
* @param width
* @param height 
* @param depth
* @param width
*/
__kernel void
avgInOut(const __global float* phi,const  __global float* img_in,
        __global float* avg_in_out, __const int size, 
        __const int cellsPerWorkItem) {

    int indx = (int)get_global_id(0)*cellsPerWorkItem;//Start index for this work item
    int origIndx = indx;//Save the initial index
    int totalWorkItems = (int)get_local_size(0);//Items in this group

    float value = 0;

    //This are local variables to compute the final reduction
    local int currCountOutAll;
    local int currCountInAll;
    local int currSumOutAll;
    local int currSumInAll;

    // Only first thread initializes these local variables
    if( get_local_id(0) == 0){
        currCountOutAll= 0;
        currCountInAll = 0;
        currSumOutAll = 0;
        currSumInAll = 0;
    }

    //This are private variables to compute reduction
    float currSumIn = 0;
    float currSumOut = 0;
    int currCountIn = 0;
    int currCountOut = 0;
    int iter = 0;

    while(indx < size){//Indicates when each thread should stop
		//This is the number of cells that are computed for each thread
        for(int i = 0; i < cellsPerWorkItem; i++){
            if(indx < size){
                value = img_in[indx];
                if(phi[indx] <= 0){
                    // Pixels outside the mask
                    currSumOut = currSumOut + value;
                    // Count pixels outside the mask
                    currCountOut = currCountOut + 1;
                }else{
                    // Pixels inside the mask
                    currSumIn = currSumIn + value;
                    // Count pixels inside the mask
                    currCountIn = currCountIn + 1;
                }
            }else{//We already finish
                break;
            }
            indx ++;//We increment the current index
        }//For

        // Assuming that we are using the right amount of memory is better if wersynchronize here

        iter++;// Increment the iteration we are computing
        indx = (int)origIndx + iter*cellsPerWorkItem*totalWorkItems;
    }

    //Adding atomically to the output variable
    atomic_add(&currCountOutAll, currCountOut);
    atomic_add(&currCountInAll, currCountIn);
    atomic_add(&currSumInAll, (int)currSumOut);
    atomic_add(&currSumOutAll,(int)currSumIn);

    barrier(CLK_LOCAL_MEM_FENCE);

    // Only thread 1 makes the final computation
    if( get_local_id(0) == 0){
        avg_in_out[0] = (float)currSumOutAll/(float)currCountOutAll;
        avg_in_out[1] = (float)(currSumInAll/(float)currCountInAll);
        //avg_in_out[0] = currCountOutAll;
        //avg_in_out[1] = currCountInAll;
    }
}
/**
 * Obtains the average value of an array. For this specific case
 * we are computing two different averages, oner for the odd
 * values and one for the even valus of the array.
 */
__kernel void
Step2AvgInOut(global float* avgDistInOut, global int* avgCount) {

    int col = (int)get_global_id(0);

    int grp_indx = (get_group_id(1) * get_num_groups(0) + get_group_id(0));

    // We will double the group size, setting on the even indexes the inside values
    // and on the odd indexes the out values
    int indxIn = grp_indx*2;
    int indxOut = grp_indx*2 + 1;

    // Shared variables among the local threads
    local int sumIn;
    local int sumOut;
    local int countIn;
    local int countOut;

    // Only first thread initializes the local variables
    if( get_local_id(0) == 0 && get_local_id(1) == 0){
        sumIn = 0;
        sumOut = 0;
        countIn = 0;
        countOut = 0;
    }	

    // Reads the average value
    float value = avgDistInOut[col];
    int count = avgCount[col];

    barrier(CLK_LOCAL_MEM_FENCE);

    // Adds the value to the positive or negative index
    if(count > 0){
        if( fmod((float)col,(float)2) == 0){//If it is an even index then it belongs to the sumIn values
            atomic_add(&sumIn, value);
            atomic_add(&countIn, count);
        }else{// If it is an odd index, then it belongs to the avg out values.
            atomic_add(&sumOut, value);
            atomic_add(&countOut, count);
        }
    }

    barrier(CLK_LOCAL_MEM_FENCE);

    // Only the first thread of each group computes the final averages
    if( get_local_id(0) == 0 && get_local_id(1) == 0){
        if( (get_num_groups(0) == 1) && (get_num_groups(1) == 1) ){ // In this case this is the last iteation

            if(countIn > 0){ avgDistInOut[indxIn] = (float)sumIn/countIn; }
            else{avgDistInOut[indxIn] = 0; }

            if(countOut > 0){ avgDistInOut[indxOut] = (float)sumOut/countOut; }
            else{avgDistInOut[indxOut] = 0; }

        }else{// Normal iteration, not the last one
            if(countIn > 0){ avgDistInOut[indxIn] = (float)sumIn; }
            else{avgDistInOut[indxIn] = 0; }

            if(countOut > 0){ avgDistInOut[indxOut] = (float)sumOut; }
            else{avgDistInOut[indxIn] = 0; }

        }
    }

    // Only the second thread adds to the counts
    if( get_local_id(0) == 1 && get_local_id(1) == 0){

        if( (get_num_groups(0) == 1) && (get_num_groups(1) == 1) ){ // In this case this is the last iteation
            if(countIn > 0){ avgCount[indxIn] = 1; }//We already have the average
            if(countOut > 0){ avgCount[indxOut] = 1; }
        }else{
            avgCount[indxIn] = countIn; 
            avgCount[indxOut] = countOut;
        }
    }
}
