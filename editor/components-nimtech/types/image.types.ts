export interface MarImageFrame {
  /** Left edge of the selected region as a fraction of the image width. */
  x: number;
  /** Top edge of the selected region as a fraction of the image height. */
  y: number;
  /**
   * Width of the selected region as a fraction of the image width.
   * @minimum 0.05
   * @maximum 1
   */
  width: number;
  /**
   * Height of the selected region as a fraction of the image height.
   * @minimum 0.05
   * @maximum 1
   */
  height: number;
}
