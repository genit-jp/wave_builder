class ByteUtils {
  static List<int> numberAsByteList(int input, numBytes, {bigEndian = true}) {
    var output = <int>[];
    int curByte = input;
    for (var i = 0; i < numBytes; ++i) {
      output.insert(bigEndian ? 0 : output.length, curByte & 255);
      curByte >>= 8;
    }
    return output;
  }

  static int byteListAsNumber(List<int> input, {bigEndian = true}) {
    int output = input[0];

    for (var i = 0; i < input.length; ++i) {
      bigEndian
          ? output |= input[i] << 8 * (i)
          : output |= input[i] << 8 * (input.length - i);
    }

    return output;
  }

  static int findByteSequenceInList(List<int> sequence, List<int> list) {
    for (var outer = 0; outer < list.length; ++outer) {
      var inner = 0;
      for (;
          inner < sequence.length &&
              inner + outer < list.length &&
              sequence[inner] == list[outer + inner];
          ++inner) {}
      if (inner == sequence.length) {
        return outer;
      }
    }
    return -1;
  }
}
