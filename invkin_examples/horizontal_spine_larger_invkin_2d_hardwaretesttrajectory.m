%% horizontal_spine_larger_invkin_2d_hardwaretesttrajectory.m
% Copyright Andrew P. Sabelhaus 2019

% This script used the tInvKin libraries to calculate the optimal
% equilibrium inputs for a single vertebra, 2D tensegrity spine: the larger
% one used for the spring/summer 2019 data collection.

% The 'trajectory' script here outputs a sequence of equilibrium rest
% length solutions, for use with control.

% Modified from original ..._trajectory script to accomodate for the small
% geometric differences with the hardware test setup.

%% set up the workspace
clear all;
close all;
clc;

% add the core libraries, assumed to be in an adjacent folder.
addpath( genpath('../invkin_core') );
% same for the plotting.
addpath( genpath('../invkin_plotting') );
% and for the trajectories, a subfolder.
addpath( genpath('./invkin_trajectories') );

%% Set up the parameters

% Debugging level.
% 0 = no output except for errors
% 1 = Starting message, results from quadprog
% 2 = Verbose output of status.
debugging = 1;

% If appropriate, output a starting message.
if debugging >= 1
    disp('Starting LARGER horizontal spine 2d rigid body inverse kinematics example...');
end

% minimum cable force density
%q_min = 0; % units of N/m, depending on m and g
q_min = 0.5;
%q_min = 0.1;

% Local frames. We're going to use the get_node_coordinates script for both
% "vertebrae", but with the "fixed" one having a different frame to account
% for the slightly different exit points of the cables from the eye hooks.

% As per Drew's sketched frames, the moving vertebra will have four nodes,
% with the local origin at the geometric center of the vertebra, and all the
% mass concentrated at node 1 (the inertial center.)
% This results in the plot being a bit off with respect to the physical
% vertebra - the pointy part of the "Y" will be longer in the visualization
% here than in the physical prototype - but the physics are the same.

% 1 = inertial center
% 2 = back bottom, 3 = back top, 4 = right.
% in cm:
c_x = 2.91;
w = 14.42;
f_x = 16.06;
h = 15.24;

% w_1 = 16.06;
% w_2 = 14.42;
% h = 15.24;
% w_5 = 2.91;

a_free = [ -c_x,        0;
           -w,         -h;
           -w,          h;
            f_x,        0]';
        
% In addition, we'll need to know where the dowel pin holes are on the
% vertebra. This is used to get the initial, untensioned pose.
% d_1 = dowel closer to CoM, d_2 = dowel closer to node 4 ("right")
% the y-coordinate here is 0.
d_1 = 0.82;
d_2 = 8.44;
        
% We now only have three nodes for the fixed vertebra. It's a triangle.
% These are in the GLOBAL frame!
% A = bottom left cable anchor,
% B = top left cable anchor,
% C = center cable anchor (both the saddle cables exit here)
A_x = 6.33;
A_y = 9.55;
B_x = 6.56;
B_y = 40.03;
C_x = 18.42;
C_y = 24.77;

% b_6 = 6.33;
% u_6 = 9.55;
% b_7 = b_6;
% u_7 = 40.03;
% b_8 = 18.42;
% u_8 = 24.77;

% 5 = bottom left (A), 6 = top left (B), 7 = center (C)
a_fixed = [ -A_x,       A_y;
            -B_x,       B_y;
             C_x,       C_y]';
         
% As with the local vertebra frame, locations of the dowel pins are needed
% to get the initial untensioned vertebra pose
% E = dowel pin closer to anchors (left),
% G = dowl pin on the right
E_x = 33.66;
E_y = 24.77;
G_x = 41.28;
G_y = 24.77;

if debugging >= 2
    a_free
    a_fixed
end

% number of rigid bodies
%b = 2;
% When removing the anchor nodes, it's like removing one of the bodies:
b = 1;

% Configuration matrix for WHOLE STRUCTURE.

% Full connectivity matrix
% Rows 1-4 are cables
% Rows 5-9 are bars
% Columns 1-3 are anchor nodes
% Columns 4-7 are free vertebra nodes

%    A  B  C  c  bb bt f
%    1  2  3  4  5  6  7  
C = [1  0  0  0  -1 0  0;  %  1, cable 1, horizontal bottom
     0  1  0  0  0  -1 0;  %  2, cable 2, horizontal top
     0  0  1  0  -1 0  0;  %  3, cable 3, saddle bottom
     0  0  1  0  0  -1 0;  %  4, cable 4, saddle top
     1  0  -1 0  0  0  0;  %  5, bar 1, bottom anchor triangle leg
     0  1  -1 0  0  0  0;  %  6, ...
     0  0  0  1 -1  0  0;  %  7, bar 3, free vertebra bar 1
     0  0  0  1  0 -1  0;  %  8, ...
     0  0  0  1  0  0 -1]; %  9, bar 6

% Need to specify number of cables, to split up C.
s = 4;
% r follows directly, it's the remainder number of rows.
r = size(C,1) - s;
% ...because C is \in R^{10 x 8}.

% number of nodes
n = size(C, 2);

if debugging >= 2
    C
end

% gravitational constant
% ON 2018-12-6: THIS MAY BE OPPOSITE? WHY?? OR NOT??
% TO-DO: FIX THIS SIGN ERROR. Gravity went "up" for earlier results??
g = 9.81;
%g = -9.81;

% Note here that I've used m_i as per-body not per-node.
% Probably accidentally changed notation w.r.t. T-CST 2018 paper.

% Mass as measured with a scale by Jacob on 2019-05-10 was 655g.
m_i = 0.655;

% 2018-12-6: let's see if we just assign all the mass to the center of mass
% node. 2019-50-13: that's node 4, little "c" Center of Mass.
m = zeros(n,1);
m(4) = m_i;
% since we're throwing out the anchor points in the force balance, leave
% those masses as zero.

% Spring constant for the cables. This isn't used in the optimization for
% force (densities) itself, but for conversion into inputs when saving the
% data.
% Here's how to specify 'the same spring constant for all cables'. In N/m.
% For the hardware test, the Jones Spring Co. #241 has a constant of 1.54
% lb/in, which is 270 N/m.
% One set of new McMaster springs is 4.79 lb/in,
% conversion is 
lbin_in_nm = 175.126835;
kappa_i = 4.79 * lbin_in_nm;
% ...which happens to be
%kappa_i = 270;
kappa = ones(s,1) * kappa_i;
% On 2018-12-6, we changed cable 3 and 4 to have a higher spring constant, so it
% has less extension, since we were running into hardware limitations.
%kappa(3) = 8.61 * lbin_in_nm;
% with the 25 lb/in spring:
kappa(3) = 25.4 * lbin_in_nm;
kappa(4) = 25.4 * lbin_in_nm;
%kappa(4) = 8.61 * lbin_in_nm;


% Some dimensions of the springs.
% We need to check for collisions / add this to the formulation as a
% constraint.
% The spring extender length (which is added to spring initial length) is 
% 1 inch, but the spring hooks to the end of the outer loop, so it's 1.13
% effectively.
extender_length = 1.13 * 2.54 * 0.01;
% The initial lengths of each of the springs used, according to those
% spring constants.
l_init_8 = 1 * 2.54 * 0.01;
l_init_4 = 1 * 2.54 * 0.01;
l_init_25 = 0.75 * 2.54 * 0.01;
% For cables 3 and 4, we also need to adjust for the little cable
% adjustment screw mechanism. It puts the spring tip at its center, and
% adds an extra few mm from its center to edge. Measured roughly (cm -> m)
adjuster_length = 0.36 * 0.01;
%initial_lengths = [l_init_4; l_init_4; l_init_8; l_init_4];
initial_lengths = [l_init_4; l_init_4; l_init_25 + adjuster_length; ...
    l_init_25 + adjuster_length];
% So, the total length to subtract from the rest length is
init_len_offset = initial_lengths + extender_length;

% Example of how to do the 'anchored' analysis.
% Declare a vector w \in R^n, 
% where w(i) == 1 if the node should be 'kept'.
% For this example, want to treat body 1 as the anchored nodes.
% So, we zero-out anchored nodes 1 through 4, and keep nodes 5-8
% (which is vertebra two.)
w = [0; 0; 0; 0; 1; 1; 1; 1];
% Including all nodes:
%w = ones(n,1);

% IMPORTANT! If chosing to remove nodes, must change 'b' also, or else inv
% kin will FAIL.

% We also need to declare which nodes are pinned (with external reaction
% forces) and which are not.
% We're choosing not to have this be the same as w, since there are some
% nodes to "ignore" for w which are not necessarily built in to the ground
% for "pinned". Example, nodes inside the leftmost vertebra, where we're
% deciding to assume that only the tips of its "Y" are supported.

% So, only nodes 1 and 4 are pinned.
pinned = zeros(n,1);
pinned(1) = 1;
pinned(4) = 1;

%% Trajectory of positions

% all the positions of each rigid body (expressed as their COM positions
% and rotation). that's 3 states: [x; z; \gamma] with
% the angle being an intrinsic rotation.

% We need the initial pose of the robot, PI_0, at which the cables are
% calibrated. This is for the hardware test: at pose PI_0, the cables are
% assumed to be at "perfectly 0 force", e.g. just barely not slack. For
% example, if we fix the spine at some position, and adjust each cable so
% it's just barely no longer slack, then we have a calibration.

% For calculations with the hardware test setup, we need to know
% where the vertebra is pinned into place for calibration. This is
% currently (as of 2018-12-10) at:
calibrated_position_free = [bar_endpoint; 0; 0];
% ...because the center of that frame is at bar_endpoint, not the CoM, and
% the robot is assumed to have zero rotation at its initial state.

% The "fixed" vertebra, the leftmost one, has no translation or rotation.
% To get the full system state, we must specify both.
calibrated_position_fixed = [0; 0; 0];

% We can then get the positions of each of the nodes. We need this for the
% initial length calculations. It's important to note that we need it for
% BOTH of these two vertebrae, which have different frames.
coordinates_calibrated_fixed = get_node_coordinates_2d(a_fixed, ...
    calibrated_position_fixed, debugging);
% and for the free vertebra
coordinates_calibrated_free = get_node_coordinates_2d(a_free, ...
    calibrated_position_free, debugging);

% We can then use the same trick from the invkin_core function to calculate
% the lengths of the cables, via the C matrix. Concatenate the node
% positions for the whole structure:
coordinates_calibrated_x = zeros(n,1);
coordinates_calibrated_y = zeros(n,1);
% The outputs from get_node_coordinates are row vectors:
coordinates_calibrated_x(1:4) = coordinates_calibrated_fixed(1,:)';
coordinates_calibrated_x(5:8) = coordinates_calibrated_free(1,:)';
coordinates_calibrated_y(1:4) = coordinates_calibrated_fixed(2,:)';
coordinates_calibrated_y(5:8) = coordinates_calibrated_free(2,:)';
% The lengths of each cable member in the two directions are (via the 
% "cable" rows of C),
dx0 = C(1:4,:) * coordinates_calibrated_x;
dy0 = C(1:4,:) * coordinates_calibrated_y;
% so the lengths of each cable are the euclidean norm of each 2-vector,
% re-organize:
D0 = [dx0, dy0];
% the row norm here is then the length.
lengths_0 = vecnorm(D0, 2, 2);

% Now, for the trajectory as the robot moves:
% The trajectory generation function gives back a sequence of states for
% which we require cable inputs.
% Let's do a trajectory that sweeps from 0 to pi/8.
%max_sweep = pi/8;
%max_sweep = pi/12;
max_sweep = pi/16;
% To swing the vertebra down slowly, do a sweep to a negative number.
%max_sweep = -pi/16;
% Now, also include a minimum. This was 0 before. Now, we can start "down"
% somewhere and bend upward.
min_sweep = -pi/16;
%min_sweep = 0;
% with the the vertebra horizontal-sideways,
% The local frame needs to be rotated by
%rotation_0 = -pi/2;
% The frames are at an initial configuration of zero rotation.
rotation_0 = 0;
% and translated outward. The test setup's default position has the free
% vertebra directly aligned with the saddle cables' eyebolt exit points,
% which, since the moving vertebra has its frame origin at the geometric
% center,
% translation_0 = [bar_endpoint; 0];
% For testing, here's a smaller fraction.
translation_0 = [bar_endpoint * (3/4); 0];
% with a large number of points.
%num_points = 400;
% For doing the hardware test: the motor controller doesn't have great
% resolution. So, do a smaller number of poins.
%num_points = 5;
%num_points = 2;
%num_points = 10;
num_points = 20;

% For the frames we've chosen, it doesn't make sense to rotate the vertebra
% around the origin: we don't want it to sweep out from the tip of the
% eyebolts, but instead from whatever the "center" of the fixed vertebra
% eyebolt pattern would be.
% That's maybe halfway between the tip and the back, or
rot_axis_pt = [back_x*(2/3); 0];

% get the trajectory:
[xi_all] = trajectory_XZT_bend_2d(translation_0, rotation_0, min_sweep, ...
    max_sweep, rot_axis_pt, num_points);

% use \xi for the system states.
%xi = zeros(b * 3, 1);

% for rigid body 1, the fixed one, doesn't move. However, we've defined it
% in its "vertical" state, so it needs to be rotated by 90 degrees around
% the y-axis so the saddle cables can align. Let's rotate it clockwise so
% that node 4 is in +x.
% xi(3) = -pi/2;

% for rigid body 2, translate out in the +x direction. Translating by one
% full body length puts the tips exactly in the same plane, so maybe do it
% to 3/4 of that length.
% the length of one vert is 2 * bar_endpoint. 
% x-position is coordinate 1.
% To make things interesting, let's rotate it a small bit, too.
%xi(3) = -pi/2 + pi/16;

% xi(4:6) = [     bar_endpoint * (3/2);
%                 0;
%                -pi/2 + pi/16];
%             
% if debugging >= 2
%     xi
% end

%% Calculations for the inputs to the core invkin library

% The nodal coordinates (x, z)
% calculate from position trajectory. 
% We can do these out for each point, along the trajectories.
% initialize the results. There are n nodes (n position vectors.)
x = zeros(n, num_points);
y = zeros(n, num_points);

for i=1:num_points
    % We split up according to rigid body. The fixed body is xi_all(1:3,i)
    coordinates_i_fixed = get_node_coordinates_2d(a_fixed, ...
        xi_all(1:3, i), debugging);
    % and for the free vertebra
    coordinates_i_free = get_node_coordinates_2d(a_free, ...
        xi_all(4:6, i), debugging);
    % At this point along the trajectory, get the coordinates
    %coordinates_i = get_node_coordinates_2d(a_free, xi_all(:,i), debugging);
    % ...and split them into coordinate-wise vectors per node, per
    % vertebra.
    x(1:4, i) = coordinates_i_fixed(1,:)';
    x(5:8, i) = coordinates_i_free(1,:)';
    y(1:4, i) = coordinates_i_fixed(2,:)';
    y(5:8, i) = coordinates_i_free(2,:)';
%     x(:,i) = coordinates_i(1,:)';
%     y(:,i) = coordinates_i(2,:)';
end
    
% coordinates = get_node_coordinates_2d(a, xi, debugging);

if debugging >= 2
    %coordinates
    x
    y
end

% Reaction forces can be calculated by this helper, which assumes that only
% gravity is present as an external force.
% Initialize results
px = zeros(n, num_points);
py = zeros(n, num_points);

% Iterate over all points:
for i=1:num_points
    % The i-th index will be columns for all these.
    [px(:,i), py(:,i)] = get_reaction_forces_2d(x(:,i), y(:,i), pinned, ...
        m, g, debugging);
end

% for more details, you can look at commits to the library before Nov. 2018
% where this reaction force/moment balance was written out by hand.

% Since this was just a calculation of the reaction forces, we ALSO need to
% add in the external forces themselves (grav forces) for use as the whole
% inverse kinematics problem.

% Add the gravitational reaction forces for each mass.
% a slight abuse of MATLAB's notation: this is vector addition, no indices
% needed, since py and m are \in R^n.
py = py + -m*g;


%% Solve the inverse kinematics problem

% Solve, over each point.
% Let's use a cell array for Ab and pb, since I don't feel like thinking
% over their sizes right now.
f_opt = zeros(s, num_points);
q_opt = zeros(s, num_points);
% we also need the lengths for calculating u from q*.
lengths = zeros(s, num_points);
Ab = {};
pb = {};

% finally, the big function call:
for i=1:num_points
    if debugging >= 1
        disp('Iteration:');
        disp(num2str(i));
    end
    % quadprog is inside this function.
    [f_opt(:,i), q_opt(:,i), lengths(:,i), Ab_i, pb_i] = invkin_core_2d_rb(x(:,i), ...
        y(:,i), px(:,i), py(:,i), w, C, s, b, q_min, debugging);
    % and insert this Ab and pb.
    Ab{end+1} = Ab_i;
    pb{end+1} = pb_i;
end

% Seems correct, intuitively!
% Cable 1 is horizontal, below.
% Cable 2 is horizontal, above.
% Cable 3 is saddle, below.
% Cable 4 is saddle, above.

% It makes sense that cable 2 force > cable 1 force, for an "upward" force
% in the saggital plane, counteracting gravity on the suspended vertebra.
% it then also could make sense that cable 3 has no force: the
% gravitational force on the suspended vertebra gives a clockwise moment,
% which is also the direction of cable 3.
% Cable 4's force is likely counteracting the gravitational moment of the
% suspending vertebra.

% TO-DO: Confirm, by hand/in simulation, that these forces actually keep
% the vertebra in static equilibrium.

% TO-DO: sign check. Are we applying positive tension forces or negative
% tension forces? See if/what solution pops out with the constraint in the
% opposite direction (< c, not > c.)

% A quick plot of the cable tensions.
figure; 
hold on;
subplot(4,1,1)
hold on;
title('Cable tensions');
plot(f_opt(1,:))
ylabel('1 (N)');
subplot(4,1,2)
plot(f_opt(2,:))
ylabel('2 (N)');
subplot(4,1,3)
plot(f_opt(3,:))
ylabel('3 (N)');
subplot(4,1,4);
plot(f_opt(4,:));
ylabel('4 (N)');

%% Convert the optimal forces into optimal rest lengths.
% u_i = l_i - (F_i/kappa_i)

% save in a vector
u_opt = zeros(s, num_points);
% it's more intuitive to iterate for now. At least, we can iterate over
% cables and not over timesteps.
for k=1:s
    % For cable k, divide the row in f_opt by kappa(k)
    % But, now include the length offset term. Accounts for the initial
    % spring length, as well as the little extender we had to use.
    %u_opt(k, :) = lengths(k,:) - init_len_offset(k) - (f_opt(k,:) ./ kappa(k));
    u_opt(k, :) = lengths(k,:) - (f_opt(k,:) ./ kappa(k));
end

% For use with the hardware example, it's easier to instead define a
% control input that's the amount of "stretch" a cable experiences.
% Note that we also save a difference from Pi_0, the calibrated position.
% Some algebra shows that the control input here is stretch added to the
% delta of absolute cable lengths from Pi_0 to lengths_i.
stretch_opt = zeros(s, num_points);
lengths_diff = zeros(s, num_points);
stretch_opt_adj = zeros(s, num_points);
for k=1:s
    % For cable k, divide the row in f_opt by kappa(k)
    stretch_opt(k, :) = (f_opt(k,:) ./ kappa(k));
    % the length difference is a subtraction from the initial pose
    % note that lengths_0 is transposed as calculated above.
    % We're iterating over cables, so need to index into the initial
    % lengths. Abusing some MATLAb broadcasting here (properly, ones(1,k)
    % multiplied by lengths_0(k).)
    lengths_diff(k,:) = lengths_0(k)' - lengths(k,:);
    % and then add to the adjusted stretch,
    % ALSO SCALE TO GET CM, since the microcontroller uses that best, not
    % meters.
    stretch_opt_adj(k,:) = (stretch_opt(k,:) + lengths_diff(k,:)) * 100;
end

% % Now, we have to adjust by the offsets in position, since the total length
% % changes. First, the difference between the calibrated position and the
% % initial equilibrium state will be needed to be subtracted away.
% % The length calculation for the calibrated position can be done as
% 
% % The locations of each of the nodes for the moving vertebra:
% calibrated_nodes_free = a_free + calibrated_position;
% calibrated_nodes_fixed = a_fixed;
% calibrated_nodes_x(1:4, i) = calibrated_nodes_fixed(1,:)';
% calibrated_nodes_x(5:8, i) = calibrated_nodes_free(1,:)';
% calibrated_nodes_y(1:4, i) = calibrated_nodes_fixed(2,:)';
% calibrated_nodes_y(5:8, i) = calibrated_nodes_free(2,:)';
% %H_hat = [eye(s), zeros(s, r)];
% % all the lengths of each cable are:
% dx0 = C(1:4,:) * calibrated_nodes_x;
% dz0 = C(1:4,:) * calibrated_nodes_y;
% 
% % so the lengths of each cable are the euclidean norm of each 2-vector.
% % re-organize:
% D0 = [dx0, dz0];

% % the scalar lengths are then the 2-norm (euclidean) for each column, which
% % is
% % lengths_0 = vecnorm(D0, 2, 2);
% % the difference that needs to be added is this amount minus current
% % length.
% % in cm:
% lengths_adj = (lengths_0 - lengths)*100;
% 
% % the stretches then will be adjusted by this amount. Needs to be additive.
% stretch_opt = stretch_opt + lengths_adj;

% A quick plot of the changes in cable lengths.
figure; 
hold on;
subplot(4,1,1)
hold on;
title('Cable Inputs (Amount of Retraction From Calibration)');
plot(stretch_opt_adj(1,:))
ylabel('1 (cm)');
subplot(4,1,2)
plot(stretch_opt_adj(2,:))
ylabel('2 (cm)');
subplot(4,1,3)
plot(stretch_opt_adj(3,:))
ylabel('3 (cm)');
subplot(4,1,4);
plot(stretch_opt_adj(4,:));
ylabel('4 (cm)');

%% Plot the structure, for reference.

% This should make it easier to visualize the results.
% Need to specify "how big" we want the bars to be. A good number is
radius = 0.005; % meters.

% Plotting: do the first position and the last position.
% Basic command:
% plot_2d_tensegrity_invkin(C, x, y, s, radius);
% We want to get the first and last coordinates.
% Reference configuration state:
plot_2d_tensegrity_invkin(C, coordinates_calibrated_x, coordinates_calibrated_y, s, radius);
% Initial position:
plot_2d_tensegrity_invkin(C, x(:,1), y(:,1), s, radius);
% Final position:
plot_2d_tensegrity_invkin(C, x(:,end), y(:,end), s, radius);

% In order to use this date

%% Save the data.

% path to store: ***CHANGE THIS PER-USER***
% for now, use the user's home directory.
savefile_path = '~/';

% As a final hack for mid-december 2018, to correlate with the computer
% vision data, express the states in terms of their center of mass.
% This is because the the tracking marker on the spine vertebra is at the
% CoM not the geometric center of the local frame of the moving vertebra.
xi_moving = xi_all(4:6, :);
com_offset = [center_x; 0];
% rotate the CoM offset by the body's rotation, and then add it back in to
% each state.
for t=1:num_points
    % Rotate for this timestep
    gamma = xi_moving(3, t);
    rot = [cos(gamma),  -sin(gamma);
           sin(gamma),   cos(gamma)]; 
    com_adjusted = rot * com_offset;
    % add it back in.
    xi_moving(1:2, t) = xi_moving(1:2, t) + com_adjusted;
end

% recombined the states
%xi_all(4:6, :) = xi_moving;

% write the actual data
% we used the rigid body reformulation method here, 
n_or_b = 1;
%save_invkin_results_2d(u_opt, xi_all, n, r, n_or_b, savefile_path);
% For the hardware test, we want to use "stretch" not rest length.
%save_invkin_results_2d(stretch_opt_adj, xi_all, n, r, n_or_b, savefile_path);














