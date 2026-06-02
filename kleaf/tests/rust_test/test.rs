// SPDX-License-Identifier: GPL-2.0-only

extern crate point_bindgen;

#[test]
fn test_point() {
    let p = point_bindgen::Point { x: 1, y: 2 };
    assert_eq!(p.x, 1);
    assert_eq!(p.y, 2);
}
