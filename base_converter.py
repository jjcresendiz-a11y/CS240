print("Number Base Converter")

base = int(input("Enter the current base (2, 8, 10, or 16): "))
number = input("Enter the number: ")

decimal_value = int(number, base)

eight_bit_value = decimal_value % 256

print("Binary:", format(eight_bit_value, "08b"))
print("Decimal:", decimal_value)
print("Octal:", format(eight_bit_value, "o"))
print("Hexadecimal:", format(eight_bit_value, "02X"))
