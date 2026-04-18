// ============================================================
// Letter Plinth with Textured Surface
// ============================================================
// Generates a flat plinth with a raised, bump-textured letter.
// Designed to work with the OpenSCAD Customizer.
// ============================================================


/* [Letter] */

// The character to display on the plinth
letter = "A"; // ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z","1","2","3","4","5","6","7","8","9","0"]


/* [Plinth Dimensions] */

// Overall height of the plinth base (mm)
plinth_height = 140;

// Thickness of the plinth base slab (mm)
plinth_thickness = 1.5;

// Left margin before the letter starts (mm)
plinth_width_left = 25;

// Right margin after the letter ends (mm)
plinth_width_right = 25;


/* [Letter Dimensions] */

// Font size of the letter (mm)
letter_size = 150;

// How far the letter is raised above the plinth surface (mm)
letter_extrude_height = 2;

// Y-axis offset of the letter from the bottom of the plinth (mm)
letter_y_offset = 25;


/* [Texture Settings] */

// Width of the texture field (mm) — should cover the plinth width
texture_width = 200;

// Height of the texture field (mm) — should cover the plinth height
texture_height = 200;

// Spacing between bump centres (mm); smaller = denser texture
bump_spacing = 1;

// Radius of each spherical bump (mm)
bump_radius = 1;

// Sphere resolution for bumps ($fn); lower = faster preview
bump_fn = 12;


/* [Hidden] */
// Global minimum fragment size for preview performance
$fs = 0.5;


// ============================================================
// Module: plinth
// Draws the flat rectangular base slab in black.
// Dimensions: 185 wide × 190 deep × plinth_thickness tall.
// ============================================================
module plinth() {
    color("black") {
        cube([185, 190, plinth_thickness]);
    }
}


// ============================================================
// Module: letter_profile
// Produces a 2D-extruded solid letter shape used both as the
// raised insert and as a clipping mask for the texture.
// ============================================================
module letter_profile() {
    translate([plinth_width_left, letter_y_offset, 0])
        linear_extrude(height = letter_extrude_height)
            text(letter,
                 size  = letter_size,
                 font  = "Atkinson Hyperlegible Next:style=Medium");
}
// ============================================================
// Module: letter_mask
// A taller version of the letter used exclusively as the
// intersection clip volume for the bump texture.
//
// Why taller? Bump spheres are centred at letter_extrude_height,
// so their top halves reach to letter_extrude_height + bump_radius.
// The mask must extend at least that high or the upper portion of
// every sphere escapes the intersection and bleeds outside the letter.
//
// Mask height = letter_extrude_height + bump_radius + small epsilon
// to guarantee full containment regardless of $fs rounding.
// ============================================================
module letter_mask() {
    translate([plinth_width_left, letter_y_offset, 0])
        linear_extrude(height = letter_extrude_height + bump_radius + 0.01)
            text(letter,
                 size  = letter_size,
                 font  = "Atkinson Hyperlegible Next:style=Medium");
}


// ============================================================
// Module: texture
// Creates a grid of small spherical bumps across a w × h field.
// Bump centres sit exactly on the top face of the letter so that
// each sphere is half-embedded, half-proud — fully clipped by
// letter_mask inside textured_letter.
// Parameters:
//   w       — width of the bump field (mm)
//   h       — height of the bump field (mm)
//   spacing — centre-to-centre distance between bumps (mm)
//   bump_r  — radius of each sphere (mm)
// ============================================================
module texture(w, h, spacing = bump_spacing, bump_r = bump_radius) {
    color("yellow") {
        for (x = [0 : spacing : w])
            for (y = [0 : spacing : h])
                translate([x, y, 0])
                    sphere(r = bump_r, $fn = bump_fn);
    }
}


// ============================================================
// Module: textured_letter
// Combines:
//   1. A solid raised letter (letter_profile).
//   2. Bumps clipped to the letter's silhouette via intersection,
//      placed just at the top surface of the letter extrusion.
// The intersection ensures bumps only appear inside the letter.
// ============================================================
module textured_letter() {
    // Solid letter base
    letter_profile();

    // Bumps masked to the letter outline
    intersection() {
        // Clip volume: re-use the letter solid as the mask
        letter_profile();

        // Bump field, raised to sit on top of the letter surface
        translate([0, 0, letter_extrude_height - bump_radius])
            texture(w = texture_width, h = texture_height);
    }
}

//  ============================================================
// Module: textured_letter
// Combines:
//   1. A solid raised letter (letter_profile) as the base geometry.
//   2. Bumps clipped strictly to the letter's XY silhouette via
//      intersection with letter_mask, which is tall enough to
//      fully contain the bump spheres in Z.
//
// Bump centres are placed at letter_extrude_height so they sit
// on the top surface; letter_mask contains their full extent.
// ============================================================
module textured_letter() {
    // Solid letter base at its true height
    letter_profile();

    // Bumps clipped to letter outline — mask is tall enough to
    // contain the complete sphere volume including the top halves
    intersection() {
        letter_mask();

        // Centre bump spheres on the letter's top face
        translate([0, 0, letter_extrude_height])
            texture(w = texture_width, h = texture_height);
    }
}


// ============================================================
// Module: final_plate
// Top-level assembly: plinth slab + textured letter on top.
// ============================================================
module final_plate() {
    union() {
        plinth();
        textured_letter();
    }
}


// ============================================================
// Entry point — render the complete model
// ============================================================
final_plate();