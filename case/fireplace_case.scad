// Skytech 3301-PF ESPHome controller case
// ESP32-WROOM DevKit (38-pin, USB-C) + CC1101 (SMA) + SHT41 in a vented pocket.
//
// Export each part:  set `part` below (or -D 'part="lid"') and render (F6) -> STL.
//   base      - box, print open side up, no supports
//   lid       - flat lid with engraved text, print text side up, no supports
//   assembly  - preview with boards
//
// All sizes in mm. Measured values are marked (measured); others are guesses
// you may want to check against your parts.

part = "assembly";

/* [Boards] */
esp_l = 51.4;   // (measured)
esp_w = 25.8;   // (measured)
esp_t = 1.56;   // (measured)
esp_total = 26; // (measured) incl. pins + jumpers below, parts on top
esp_top = 4;    // tallest part above the PCB (WROOM shield / USB-C)
esp_below = esp_total - esp_t - esp_top;   // pins + jumpers under the board

cc_l = 29.2;    // (measured)
cc_w = 15.12;   // (measured)
cc_t = 1.9;     // (measured)
cc_total = 20;  // (measured)
cc_top = 3;
cc_below = cc_total - cc_t - cc_top;

sht_l = 13;     // (measured) pins are on the 10 mm edge
sht_w = 10;     // (measured)
sht_t = 1.6;
sht_hole = [2.0, 10.8];  // mounting hole centre from pin-edge corner (from photo, check)
sht_peg_d = 2.3;         // peg through the mounting hole
sht_standoff = 5;        // wires soldered on top, so nothing hangs below

/* [Connectors] */
usb_w = 12.5;       // opening for USB-C plug overmold
usb_h = 7.0;
usb_above_pcb = 1.6;  // USB-C centre above PCB top surface (connector on top side)
sma_d = 6.9;        // hole for SMA bulkhead thread (1/4"-36 = 6.35)

/* [Box] */
wall = 2.0;
floor_t = 2.0;
lid_t = 2.4;
clr = 1.0;          // gap between board edge and wall
boss_r = 3.5;       // corner screw bosses
pilot_d = 2.5;      // M3 self-tapping (or 4.0 for M3 heat-set inserts)
lid_hole_d = 3.4;
mount_tabs = true;  // screw tabs on the long sides
corner_r = 3;

/* [Text] */
label = "Fireplace";
font = "Liberation Sans:style=Bold";   // bundled with OpenSCAD
text_width = 48;    // text is scaled to this width
text_depth = 0.8;   // engraved depth (lid is lid_t thick)

$fn = 48;

// ---- layout (interior coordinates, origin = inner floor corner) ----
side_margin = 2 * boss_r + 0.5;               // keep boards clear of corner bosses
gap_y = 9;                                     // wiring room between the boards
IX = esp_l + 2 * clr + 3;                      // interior X
IY = side_margin + esp_w + gap_y + cc_w + side_margin;
board_z = esp_below;                           // ESP PCB bottom above floor
IH = board_z + esp_t + esp_top + 3;            // interior height (lid clearance)

esp_pos = [clr, side_margin, board_z];
cc_z = cc_below + 2;
cc_pos = [IX - clr - cc_l, IY - side_margin - cc_w, cc_z];

// SHT41 pocket: corner at -X/+Y, away from the ESP32 module (which is at +X)
part_t = 1.6;
pocket_x1 = cc_pos[0] - 1.5 - part_t;          // partition along X
pocket_y0 = side_margin + esp_w + 3;           // partition along Y

// SHT41 board origin = corner at the pin edge, pins facing -Y
sht_pos = [7, pocket_y0 + part_t + 2.5, 0];

OX = IX + 2 * wall;
OY = IY + 2 * wall;
OZ = floor_t + IH;

function boss_xy() = [[boss_r, boss_r], [IX - boss_r, boss_r],
                      [boss_r, IY - boss_r], [IX - boss_r, IY - boss_r]];

module rrect(x, y, h, r) {
  linear_extrude(h) offset(r) offset(-r) square([x, y]);
}

module slots(n, len, w = 2, pitch = 4.5) {   // vent slots along X, centred
  for (i = [0 : n - 1])
    translate([i * pitch - (n - 1) * pitch / 2 - w / 2, -len / 2])
      offset(w / 2 - 0.01) offset(-(w / 2 - 0.01)) square([w, len]);
}

module base() {
  difference() {
    union() {
      rrect(OX, OY, OZ, corner_r);
      if (mount_tabs)
        for (y = [-8, OY]) translate([OX / 2 - 9, y, 0])
          difference() {
            rrect(18, 8 + 0.01, 3, 2);
            translate([9, y < 0 ? 4 : 4, -1]) cylinder(d = 4.2, h = 5);
          }
    }
    // cavity
    translate([wall, wall, floor_t]) cube([IX, IY, IH + 1]);

    // USB-C on -X wall, centred on the ESP
    translate([-1, wall + esp_pos[1] + esp_w / 2,
               floor_t + board_z + esp_t + usb_above_pcb])
      rotate([0, 90, 0]) linear_extrude(wall + 2)
        offset(1.5) offset(-1.5) square([usb_h, usb_w], center = true);

    // SMA on +X wall, centred on the CC1101 edge
    translate([OX - wall - 1, wall + cc_pos[1] + cc_w / 2, floor_t + cc_z + cc_t / 2])
      rotate([0, 90, 0]) cylinder(d = sma_d, h = wall + 2);

    // vents: main compartment, -Y wall (low + high rows)
    for (z = [floor_t + 4, floor_t + IH - 10])
      translate([wall + IX / 2, wall + 1, z]) rotate([90, 0, 0])
        linear_extrude(wall + 2) translate([0, 3]) slots(8, 6);
    // vents: +Y wall over the CC1101
    translate([wall + cc_pos[0] + cc_l / 2, OY + 1, floor_t + IH - 10]) rotate([90, 0, 0])
      linear_extrude(wall + 2) translate([0, 3]) slots(5, 6);

    // vents: SHT41 pocket, -X wall and +Y wall
    translate([-1, wall + (pocket_y0 + part_t + IY - side_margin) / 2, floor_t + IH / 2])
      rotate([90, 0, 90]) linear_extrude(wall + 2) slots(4, IH - 10);
    translate([wall + (side_margin + pocket_x1) / 2, OY + 1, floor_t + IH / 2])
      rotate([90, 0, 0]) linear_extrude(wall + 2) slots(3, IH - 10);

    // screw pilot holes
    for (p = boss_xy()) translate([wall + p[0], wall + p[1], OZ - 12]) cylinder(d = pilot_d, h = 13);
  }

  translate([wall, wall, floor_t]) {
    // corner bosses
    for (p = boss_xy()) translate([p[0], p[1], 0])
      difference() {
        cylinder(r = boss_r, h = IH);
        translate([0, 0, IH - 12]) cylinder(d = pilot_d, h = 13);
      }

    // ESP supports: blocks under both short ends, between the header rows
    for (x = [esp_pos[0], esp_pos[0] + esp_l - 3])
      translate([x, esp_pos[1] + 5, 0]) cube([3, esp_w - 10, board_z]);
    // end stop at the far end keeps the USB-C port up against its opening
    translate([esp_pos[0] + esp_l, esp_pos[1] + 5, 0]) cube([clr, esp_w - 10, board_z + esp_t + 1.5]);

    // CC1101 support post near the SMA end (SMA nut holds the other side)
    translate([cc_pos[0] + cc_l - 9, cc_pos[1] + cc_w / 2 - 2.5, 0])
      cube([5, 5, cc_z]);

    // SHT41 pocket partitions (full height, sealed by the lid)
    difference() {
      union() {
        translate([0, pocket_y0, 0]) cube([pocket_x1 + part_t, part_t, IH]);
        translate([pocket_x1, pocket_y0, 0]) cube([part_t, IY - pocket_y0, IH]);
      }
      // wire pass-through near the floor
      translate([pocket_x1 / 2 - 3, pocket_y0 - 1, -1]) cube([6, part_t + 2, 6]);
    }

    // SHT41: lies flat, sensor up under the lid vents, pin edge toward the
    // wire pass-through. Peg goes through the board's corner mounting hole.
    translate(sht_pos) {
      translate([sht_hole[0], sht_hole[1], 0]) {
        cylinder(d = 4.5, h = sht_standoff);
        cylinder(d = sht_peg_d, h = sht_standoff + sht_t + 1);
      }
      translate([sht_w - 2, sht_hole[1], 0]) cylinder(d = 3.5, h = sht_standoff);  // rest pad
    }
  }
}

module lid_text() {
  translate([OX / 2, side_margin / 2 + wall + esp_w / 2 + 2, lid_t - text_depth])
    linear_extrude(text_depth + 1)
      resize([text_width, 0], auto = true)
        text(label, font = font, halign = "center", valign = "center", size = 10);
}

module lid() {
  difference() {
    rrect(OX, OY, lid_t, corner_r);
    for (p = boss_xy()) translate([wall + p[0], wall + p[1], -1]) cylinder(d = lid_hole_d, h = lid_t + 2);
    // vents over the SHT41 pocket
    translate([wall + (side_margin + pocket_x1) / 2, wall + (pocket_y0 + part_t + IY - side_margin) / 2, -1])
      linear_extrude(lid_t + 2) slots(3, IY - pocket_y0 - side_margin - 4);
    lid_text();
  }
}

module boards() {
  translate([wall, wall, floor_t]) {
    color("royalblue") translate(esp_pos) cube([esp_l, esp_w, esp_t]);
    color("silver") translate(esp_pos + [esp_l - 18, 4, esp_t]) cube([18, esp_w - 8, 3.2]);
    color("dimgray") translate(esp_pos + [-0.5, esp_w / 2 - 4.5, esp_t]) cube([7.5, 9, 3.2]);
    color("seagreen") translate(cc_pos) cube([cc_l, cc_w, cc_t]);
    color("purple") translate(sht_pos + [0, 0, sht_standoff]) cube([sht_w, sht_l, sht_t]);
    color("gold") translate(cc_pos + [cc_l, cc_w / 2, cc_t / 2]) rotate([0, 90, 0]) cylinder(d = 6.35, h = 9);
  }
}

if (part == "base") base();
else if (part == "lid") lid();
else {
  base();
  boards();
  %translate([0, 0, OZ + 8]) lid();
}

echo(str("Outer size: ", OX, " x ", OY, " x ", OZ + lid_t, " mm"));
