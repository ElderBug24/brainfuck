#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum bfi {
  BFI_NONE,
  BFI_RIGHT,
  BFI_LEFT,
  BFI_INC,
  BFI_DEC,
  BFI_STACKABLE,
  BFI_OUT,
  BFI_IN,
  BFI_LOOP,
  BFI_END
};

struct bf_instruction {
  uint64_t count;
  size_t ref;
  enum bfi type;
};

char* input = NULL;
int fd = -1;
int out_fd = -1;
struct bf_instruction* instructions = NULL;
size_t* loop_stack = NULL;

void cleanup(void) {
  free(input);
  free(instructions);
  free(loop_stack);

  if (fd != -1)
    close(fd);

  if (out_fd != -1)
    close(out_fd);
}

void signal_handler(int sig) {
  (void) sig;

  exit(EXIT_FAILURE);
}

int main(int argc, char** argv) {
  atexit(cleanup);
  signal(SIGINT,  signal_handler);
  signal(SIGTERM, signal_handler);
  signal(SIGHUP,  signal_handler);

  unsigned stack_size = 256;
  size_t input_len = 0;
  char* output_filepath = NULL;
  for (unsigned i = 1; i < argc; ++i) {
    if (memcmp(argv[i], "--stack", 7) == 0) {
      if (sscanf(&argv[i][7], "%u", &stack_size) != 1) {
        fprintf(stderr, "error: could not parse '%s' as a positive integer\n", &argv[i][7]);
        return EXIT_FAILURE;
      }
    } else if (memcmp(argv[i], "-s", 2) == 0) {
      if (sscanf(&argv[i][2], "%u", &stack_size) != 1) {
        fprintf(stderr, "error: could not parse '%s' as a positive integer\n", &argv[i][2]);
        return EXIT_FAILURE;
      }
    } else if (input != NULL) {
      if (output_filepath == NULL)
        output_filepath = argv[i];
      else {
        fprintf(stderr, "error: Too many arguments provided\n");
        return EXIT_FAILURE;
      }
    } else {
      fd = open(argv[i], O_RDONLY);
      if (fd == -1) {
        perror("open");
        return EXIT_FAILURE;
      }

      off_t offset = lseek(fd, 0, SEEK_END);
      if (offset == (off_t) -1) {
        perror("lseek");
        return EXIT_FAILURE;
      }
      input_len = (size_t) offset;

      if (lseek(fd, 0, SEEK_SET) == (off_t) -1) {
        perror("lseek");
        return EXIT_FAILURE;
      }

      input = malloc(offset * sizeof(char));
      if (input == NULL) {
        perror("malloc");
        return EXIT_FAILURE;
      }

      if (read(fd, input, input_len * sizeof(char)) < 0) {
        perror("read");
        return EXIT_FAILURE;
      }
    }
  }

  if (input == NULL) {
    if (!isatty(STDIN_FILENO)) {
      size_t capacity = 1024;

      input = malloc(capacity);

      if (input == NULL) {
        perror("malloc");
        return EXIT_FAILURE;
      }

      ssize_t n;
      while ((n = read(STDIN_FILENO, &input[input_len], capacity - input_len)) > 0) {
        input_len += n;
        if (input_len == capacity) {
          capacity *= 2;
          char* temp = realloc(input, capacity);
          if (temp == NULL) {
            free(input);
            perror("realloc");
            return EXIT_FAILURE;
          }
          input = temp;
        }
      }

      if (n < 0) {
        free(input);
        perror("read");
        return EXIT_FAILURE;
      }
    } else {
      fprintf(stderr, "error: No input provided\n");
      return EXIT_FAILURE;
    }
  }

  if (output_filepath == NULL)
    output_filepath = "out.asm";

  size_t instructions_capacity = 1024;
  instructions = malloc(instructions_capacity * sizeof(struct bf_instruction));
  size_t instructions_count = 0;
  enum bfi last = BFI_NONE;
  uint64_t count = 1;
  size_t loop_stack_capacity = 256;
  loop_stack = malloc(loop_stack_capacity * sizeof(size_t));
  size_t loop_stack_count = 0;
  for (size_t i = 0; i < input_len; ++i) {
    enum bfi instruction = BFI_NONE;
    switch (input[i]) {
      case '>':
        instruction = BFI_RIGHT;
        break;
      case '<':
        instruction = BFI_LEFT;
        break;
      case '+':
        instruction = BFI_INC;
        break;
      case '-':
        instruction = BFI_DEC;
        break;
      case '.':
        instruction = BFI_OUT;
        break;
      case ',':
        instruction = BFI_IN;
        break;
      case '[':
        instruction = BFI_LOOP;
        break;
      case ']':
        instruction = BFI_END;
        break;
      case ';':
        while (i < input_len && input[i] != '\n') i += 1;
        continue;
      default:
        continue;
    }

    if (instruction == last && instruction < BFI_STACKABLE)
      count += 1;
    else {
      if (last != BFI_NONE) {
        if (instructions_count == instructions_capacity) {
          instructions_capacity *= 2;
          instructions = realloc(instructions, instructions_capacity * sizeof(struct bf_instruction));
        }

        size_t ref = 0;
        if (last == BFI_LOOP) {
          if (loop_stack_count == loop_stack_capacity) {
            loop_stack_capacity *= 2;
            loop_stack = realloc(loop_stack, loop_stack_capacity * sizeof(size_t));
          }

          loop_stack[loop_stack_count++] = instructions_count;
        } else if (last == BFI_END) {
          ref = loop_stack[--loop_stack_count];
          instructions[ref].ref = instructions_count;
        }

        instructions[instructions_count++] = (struct bf_instruction) {
          .type = last,
          .ref = ref,
          .count = count
        };

        count = 1;
      }

      last = instruction;
    }
  }

  printf("output: %s\n", output_filepath);

  return EXIT_SUCCESS;
}

