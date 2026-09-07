import java.awt.Color;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.Scanner;
import javax.imageio.ImageIO;

public class PixelToImage {

    public static Color convert(String letter) {
        if (letter.equals("R")) {
            return new Color(237, 28, 36);
        } else if (letter.equals("B")) {
            return new Color(0, 0, 0);
        } else if (letter.equals("Y")) {
            return new Color(255, 242, 0);
        } else {
            return new Color(255, 255, 255);
        }
    }

    public static void main(String[] args) throws IOException {
        Scanner inputFile = new Scanner(new File("output.txt"));

        int width = 11;
        int height = 11;

        BufferedImage image =
                new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);

        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                String letter = inputFile.next();
                Color color = convert(letter);
                image.setRGB(x, y, color.getRGB());
            }
        }

        inputFile.close();

        ImageIO.write(image, "png", new File("recreated_smiley.png"));

        System.out.println("Image created: recreated_smiley.png");
    }
}
