- # CTIF Converter

  `ctif-convert.jar` is a command-line tool for converting image files into the CTIF format.

  ## Usage

  Run the converter with the following command:

  ```
  java -jar ctif-convert.jar [options] INPUT_FILE
  ```

  Replace `INPUT_FILE` with the path to the source image you want to convert.

  ## Basic Example

  ```
  java -jar ctif-convert.jar --resize-mode QUALITY_NATIVE -P preview.png -o out.ctif in.png
  ```

  This command:

  - reads `in.png` as the input image
  - converts it to CTIF format
  - writes the converted file to `out.ctif`
  - saves a preview image as `preview.png`

  ## Common Options

  - `-o`, `--output`
     Specifies the output CTIF filename.
  - `-P`, `--preview`
     Saves a preview image of the converted result.
  - `-m`, `--mode`
     Sets the target platform mode, for example `OC_TIER_3`.
  - `-W`, `--width`
     Sets the output image width.
  - `-H`, `--height`
     Sets the output image height.
  - `--resize-mode`
     Sets the resize mode. Available values: `SPEED`, `QUALITY_NATIVE`, `QUALITY`.
  - `--colorspace`
     Sets the image colorspace. Available values: `RGB`, `YUV`, `YIQ`.
  - `--dither-mode`
     Sets the dithering mode. Available values: `NONE`, `ERROR`, `ORDERED`.
  - `--dither-level`
     Controls the dithering strength from `0` to `1`.
  - `-O`, `--optimization-level`
     Sets the optimization level. Lower values are generally more accurate, while higher values are faster.

  ## Example for OpenComputers

  ```
  java -jar ctif-convert.jar -m OC_TIER_3 -O 0 --resize-mode QUALITY_NATIVE --dither-mode ERROR --dither-level 0.7 -P preview.png -o out.ctif in.png
  ```

  ## Help

  To display the full help message, run:

  ```
  java -jar ctif-convert.jar -h
  ```

  ## Notes

  - Use `preview.png` to compare conversion quality before loading the `.ctif` file into your viewer.
  - For better visual results, try different combinations of colorspace, dithering mode, and optimization level.
  - Output quality depends on both the converter settings and the limitations of the target display platform.