/// Jack Daniels' vDOT training pace table — scores 30–85.
///
/// All paces in seconds per km. Each pair is (faster_bound, slower_bound).
/// Source: Daniels' Running Formula appendix. Pure const data — no logic.
library;

// ============================================================================
// PACE RANGE — (faster, slower) in sec/km
// ============================================================================

typedef PaceRange = (int faster, int slower);

// ============================================================================
// VDOT PACES — all five training zones for one vDOT score
// ============================================================================

class VdotPaces {
  /// Easy aerobic — wide range, conversational effort (59–74% vVO2max).
  final PaceRange ePaceSecPerKm;

  /// Marathon pace — race-effort, steady-state aerobic.
  final PaceRange mPaceSecPerKm;

  /// Threshold / tempo — comfortably hard, ~1-hour race effort.
  final PaceRange tPaceSecPerKm;

  /// Interval — VO2max, approximately 5K race pace.
  final PaceRange iPaceSecPerKm;

  /// Repetition — neuromuscular speed, faster than 5K pace.
  final PaceRange rPaceSecPerKm;

  const VdotPaces({
    required this.ePaceSecPerKm,
    required this.mPaceSecPerKm,
    required this.tPaceSecPerKm,
    required this.iPaceSecPerKm,
    required this.rPaceSecPerKm,
  });
}

// ============================================================================
// VDOT TABLE — scores 30–85 (56 entries)
// ============================================================================

const Map<int, VdotPaces> kVdotTable = {
  30: VdotPaces(ePaceSecPerKm: (484, 534), mPaceSecPerKm: (440, 450), tPaceSecPerKm: (398, 408), iPaceSecPerKm: (347, 357), rPaceSecPerKm: (336, 342)),
  31: VdotPaces(ePaceSecPerKm: (474, 524), mPaceSecPerKm: (433, 443), tPaceSecPerKm: (389, 399), iPaceSecPerKm: (340, 350), rPaceSecPerKm: (329, 335)),
  32: VdotPaces(ePaceSecPerKm: (464, 514), mPaceSecPerKm: (426, 436), tPaceSecPerKm: (380, 390), iPaceSecPerKm: (332, 342), rPaceSecPerKm: (321, 327)),
  33: VdotPaces(ePaceSecPerKm: (454, 504), mPaceSecPerKm: (419, 429), tPaceSecPerKm: (371, 381), iPaceSecPerKm: (325, 335), rPaceSecPerKm: (314, 320)),
  34: VdotPaces(ePaceSecPerKm: (445, 494), mPaceSecPerKm: (412, 422), tPaceSecPerKm: (362, 372), iPaceSecPerKm: (318, 328), rPaceSecPerKm: (306, 312)),
  35: VdotPaces(ePaceSecPerKm: (435, 484), mPaceSecPerKm: (405, 415), tPaceSecPerKm: (353, 363), iPaceSecPerKm: (310, 320), rPaceSecPerKm: (299, 305)),
  36: VdotPaces(ePaceSecPerKm: (428, 477), mPaceSecPerKm: (398, 408), tPaceSecPerKm: (347, 357), iPaceSecPerKm: (304, 314), rPaceSecPerKm: (294, 300)),
  37: VdotPaces(ePaceSecPerKm: (420, 469), mPaceSecPerKm: (391, 401), tPaceSecPerKm: (340, 350), iPaceSecPerKm: (299, 309), rPaceSecPerKm: (288, 294)),
  38: VdotPaces(ePaceSecPerKm: (413, 462), mPaceSecPerKm: (384, 394), tPaceSecPerKm: (333, 343), iPaceSecPerKm: (293, 303), rPaceSecPerKm: (282, 288)),
  39: VdotPaces(ePaceSecPerKm: (405, 454), mPaceSecPerKm: (377, 387), tPaceSecPerKm: (327, 337), iPaceSecPerKm: (288, 298), rPaceSecPerKm: (277, 283)),
  40: VdotPaces(ePaceSecPerKm: (398, 447), mPaceSecPerKm: (371, 381), tPaceSecPerKm: (320, 330), iPaceSecPerKm: (282, 292), rPaceSecPerKm: (271, 277)),
  41: VdotPaces(ePaceSecPerKm: (392, 441), mPaceSecPerKm: (366, 376), tPaceSecPerKm: (315, 325), iPaceSecPerKm: (277, 287), rPaceSecPerKm: (266, 272)),
  42: VdotPaces(ePaceSecPerKm: (387, 435), mPaceSecPerKm: (361, 371), tPaceSecPerKm: (310, 320), iPaceSecPerKm: (273, 283), rPaceSecPerKm: (262, 268)),
  43: VdotPaces(ePaceSecPerKm: (381, 429), mPaceSecPerKm: (355, 365), tPaceSecPerKm: (304, 314), iPaceSecPerKm: (268, 278), rPaceSecPerKm: (257, 263)),
  44: VdotPaces(ePaceSecPerKm: (376, 424), mPaceSecPerKm: (350, 360), tPaceSecPerKm: (299, 309), iPaceSecPerKm: (263, 273), rPaceSecPerKm: (252, 258)),
  45: VdotPaces(ePaceSecPerKm: (370, 418), mPaceSecPerKm: (344, 354), tPaceSecPerKm: (294, 304), iPaceSecPerKm: (259, 269), rPaceSecPerKm: (248, 254)),
  46: VdotPaces(ePaceSecPerKm: (365, 413), mPaceSecPerKm: (340, 350), tPaceSecPerKm: (290, 300), iPaceSecPerKm: (255, 265), rPaceSecPerKm: (244, 250)),
  47: VdotPaces(ePaceSecPerKm: (361, 408), mPaceSecPerKm: (336, 346), tPaceSecPerKm: (286, 296), iPaceSecPerKm: (252, 262), rPaceSecPerKm: (240, 246)),
  48: VdotPaces(ePaceSecPerKm: (356, 404), mPaceSecPerKm: (332, 342), tPaceSecPerKm: (281, 291), iPaceSecPerKm: (248, 258), rPaceSecPerKm: (236, 242)),
  49: VdotPaces(ePaceSecPerKm: (351, 399), mPaceSecPerKm: (327, 337), tPaceSecPerKm: (277, 287), iPaceSecPerKm: (245, 255), rPaceSecPerKm: (232, 238)),
  50: VdotPaces(ePaceSecPerKm: (347, 395), mPaceSecPerKm: (323, 333), tPaceSecPerKm: (273, 283), iPaceSecPerKm: (241, 251), rPaceSecPerKm: (229, 235)),
  51: VdotPaces(ePaceSecPerKm: (343, 391), mPaceSecPerKm: (319, 329), tPaceSecPerKm: (270, 280), iPaceSecPerKm: (238, 248), rPaceSecPerKm: (226, 232)),
  52: VdotPaces(ePaceSecPerKm: (339, 387), mPaceSecPerKm: (316, 326), tPaceSecPerKm: (266, 276), iPaceSecPerKm: (235, 245), rPaceSecPerKm: (223, 229)),
  53: VdotPaces(ePaceSecPerKm: (336, 383), mPaceSecPerKm: (312, 322), tPaceSecPerKm: (263, 273), iPaceSecPerKm: (232, 242), rPaceSecPerKm: (220, 226)),
  54: VdotPaces(ePaceSecPerKm: (332, 380), mPaceSecPerKm: (309, 319), tPaceSecPerKm: (259, 269), iPaceSecPerKm: (228, 238), rPaceSecPerKm: (217, 223)),
  55: VdotPaces(ePaceSecPerKm: (328, 376), mPaceSecPerKm: (305, 315), tPaceSecPerKm: (256, 266), iPaceSecPerKm: (225, 235), rPaceSecPerKm: (214, 220)),
  56: VdotPaces(ePaceSecPerKm: (325, 373), mPaceSecPerKm: (302, 312), tPaceSecPerKm: (253, 263), iPaceSecPerKm: (222, 232), rPaceSecPerKm: (212, 218)),
  57: VdotPaces(ePaceSecPerKm: (322, 370), mPaceSecPerKm: (299, 309), tPaceSecPerKm: (250, 260), iPaceSecPerKm: (220, 230), rPaceSecPerKm: (209, 215)),
  58: VdotPaces(ePaceSecPerKm: (319, 366), mPaceSecPerKm: (297, 307), tPaceSecPerKm: (248, 258), iPaceSecPerKm: (217, 227), rPaceSecPerKm: (207, 213)),
  59: VdotPaces(ePaceSecPerKm: (316, 362), mPaceSecPerKm: (294, 304), tPaceSecPerKm: (245, 255), iPaceSecPerKm: (215, 225), rPaceSecPerKm: (204, 210)),
  60: VdotPaces(ePaceSecPerKm: (313, 359), mPaceSecPerKm: (291, 301), tPaceSecPerKm: (242, 252), iPaceSecPerKm: (212, 222), rPaceSecPerKm: (202, 208)),
  61: VdotPaces(ePaceSecPerKm: (310, 356), mPaceSecPerKm: (289, 299), tPaceSecPerKm: (240, 250), iPaceSecPerKm: (210, 220), rPaceSecPerKm: (200, 206)),
  62: VdotPaces(ePaceSecPerKm: (308, 353), mPaceSecPerKm: (286, 296), tPaceSecPerKm: (237, 247), iPaceSecPerKm: (208, 218), rPaceSecPerKm: (198, 204)),
  63: VdotPaces(ePaceSecPerKm: (305, 350), mPaceSecPerKm: (284, 294), tPaceSecPerKm: (235, 245), iPaceSecPerKm: (206, 216), rPaceSecPerKm: (196, 202)),
  64: VdotPaces(ePaceSecPerKm: (303, 347), mPaceSecPerKm: (282, 292), tPaceSecPerKm: (232, 242), iPaceSecPerKm: (204, 214), rPaceSecPerKm: (194, 200)),
  65: VdotPaces(ePaceSecPerKm: (300, 344), mPaceSecPerKm: (279, 289), tPaceSecPerKm: (230, 240), iPaceSecPerKm: (201, 211), rPaceSecPerKm: (192, 198)),
  66: VdotPaces(ePaceSecPerKm: (298, 341), mPaceSecPerKm: (277, 287), tPaceSecPerKm: (228, 238), iPaceSecPerKm: (199, 209), rPaceSecPerKm: (190, 196)),
  67: VdotPaces(ePaceSecPerKm: (296, 339), mPaceSecPerKm: (275, 285), tPaceSecPerKm: (226, 236), iPaceSecPerKm: (197, 207), rPaceSecPerKm: (189, 195)),
  68: VdotPaces(ePaceSecPerKm: (294, 336), mPaceSecPerKm: (273, 283), tPaceSecPerKm: (224, 234), iPaceSecPerKm: (195, 205), rPaceSecPerKm: (187, 193)),
  69: VdotPaces(ePaceSecPerKm: (291, 333), mPaceSecPerKm: (271, 281), tPaceSecPerKm: (222, 232), iPaceSecPerKm: (193, 203), rPaceSecPerKm: (185, 191)),
  70: VdotPaces(ePaceSecPerKm: (289, 331), mPaceSecPerKm: (269, 279), tPaceSecPerKm: (220, 230), iPaceSecPerKm: (192, 202), rPaceSecPerKm: (183, 189)),
  71: VdotPaces(ePaceSecPerKm: (287, 328), mPaceSecPerKm: (267, 277), tPaceSecPerKm: (218, 228), iPaceSecPerKm: (190, 200), rPaceSecPerKm: (181, 187)),
  72: VdotPaces(ePaceSecPerKm: (285, 326), mPaceSecPerKm: (265, 275), tPaceSecPerKm: (216, 226), iPaceSecPerKm: (189, 199), rPaceSecPerKm: (180, 186)),
  73: VdotPaces(ePaceSecPerKm: (284, 323), mPaceSecPerKm: (263, 273), tPaceSecPerKm: (214, 224), iPaceSecPerKm: (187, 197), rPaceSecPerKm: (178, 184)),
  74: VdotPaces(ePaceSecPerKm: (282, 321), mPaceSecPerKm: (261, 271), tPaceSecPerKm: (213, 223), iPaceSecPerKm: (185, 195), rPaceSecPerKm: (177, 183)),
  75: VdotPaces(ePaceSecPerKm: (280, 318), mPaceSecPerKm: (259, 269), tPaceSecPerKm: (211, 221), iPaceSecPerKm: (183, 193), rPaceSecPerKm: (175, 181)),
  76: VdotPaces(ePaceSecPerKm: (278, 315), mPaceSecPerKm: (257, 267), tPaceSecPerKm: (209, 219), iPaceSecPerKm: (181, 191), rPaceSecPerKm: (174, 180)),
  77: VdotPaces(ePaceSecPerKm: (277, 313), mPaceSecPerKm: (256, 266), tPaceSecPerKm: (208, 218), iPaceSecPerKm: (180, 190), rPaceSecPerKm: (172, 178)),
  78: VdotPaces(ePaceSecPerKm: (275, 310), mPaceSecPerKm: (254, 264), tPaceSecPerKm: (206, 216), iPaceSecPerKm: (178, 188), rPaceSecPerKm: (171, 177)),
  79: VdotPaces(ePaceSecPerKm: (274, 308), mPaceSecPerKm: (252, 262), tPaceSecPerKm: (205, 215), iPaceSecPerKm: (177, 187), rPaceSecPerKm: (170, 176)),
  80: VdotPaces(ePaceSecPerKm: (272, 305), mPaceSecPerKm: (251, 261), tPaceSecPerKm: (203, 213), iPaceSecPerKm: (175, 185), rPaceSecPerKm: (169, 175)),
  81: VdotPaces(ePaceSecPerKm: (271, 303), mPaceSecPerKm: (249, 259), tPaceSecPerKm: (202, 212), iPaceSecPerKm: (174, 184), rPaceSecPerKm: (168, 174)),
  82: VdotPaces(ePaceSecPerKm: (269, 301), mPaceSecPerKm: (248, 258), tPaceSecPerKm: (200, 210), iPaceSecPerKm: (172, 182), rPaceSecPerKm: (167, 173)),
  83: VdotPaces(ePaceSecPerKm: (268, 298), mPaceSecPerKm: (246, 256), tPaceSecPerKm: (199, 209), iPaceSecPerKm: (171, 181), rPaceSecPerKm: (166, 172)),
  84: VdotPaces(ePaceSecPerKm: (267, 296), mPaceSecPerKm: (245, 255), tPaceSecPerKm: (197, 207), iPaceSecPerKm: (169, 179), rPaceSecPerKm: (164, 170)),
  85: VdotPaces(ePaceSecPerKm: (265, 294), mPaceSecPerKm: (243, 253), tPaceSecPerKm: (196, 206), iPaceSecPerKm: (168, 178), rPaceSecPerKm: (163, 169)),
};
