import struct
import os

# Constants from LPFS.asm and project structure
FS_MAGIC = 0x4C504653
SUPERBLOCK_SECTOR = 6
INODE_TABLE_SECTOR = 7
ROOT_DIR_SECTOR = 20
DATA_START_SECTOR = 20
BLOCK_SIZE = 512
IMAGE_SIZE = 1440 * 1024
KERNEL_START_SECTOR = 2

def write_sector(image_file, sector, data):
    """Writes data to a specific sector in the image file."""
    image_file.seek(sector * BLOCK_SIZE)
    if len(data) > BLOCK_SIZE:
        raise ValueError(f"Data for sector {sector} exceeds BLOCK_SIZE")
    # Pad the data to fill the entire sector
    data = data.ljust(BLOCK_SIZE, b'\x00')
    image_file.write(data)

def main():
    """Main function to create the floppy image."""
    # Ensure the build directory exists
    if not os.path.exists('build'):
        os.makedirs('build')

    # 1. Create a zero-filled image file
    with open('build/MMT.img', 'wb') as f:
        f.write(b'\x00' * IMAGE_SIZE)

        # 2. Write the bootloader to sector 0
        try:
            with open('build/bootloader.bin', 'rb') as bootloader:
                write_sector(f, 0, bootloader.read())
        except FileNotFoundError:
            print("Error: build/bootloader.bin not found. Run make to compile.")
            return

        # 3. Write the kernel to sectors starting from KERNEL_START_SECTOR
        try:
            with open('build/kernel.bin', 'rb') as kernel:
                kernel_data = kernel.read()
                num_sectors = (len(kernel_data) + BLOCK_SIZE - 1) // BLOCK_SIZE
                for i in range(num_sectors):
                    chunk = kernel_data[i*BLOCK_SIZE:(i+1)*BLOCK_SIZE]
                    write_sector(f, KERNEL_START_SECTOR + i, chunk)
        except FileNotFoundError:
            print("Error: build/kernel.bin not found. Run make to compile.")
            return

        # 4. Create and write the LPFS metadata structures
        # Superblock
        total_blocks = IMAGE_SIZE // BLOCK_SIZE
        inode_blocks = 1  # Simplified: inode table fits in one block
        data_blocks = total_blocks - DATA_START_SECTOR
        superblock_data = struct.pack(
            '<IIIIH',  # Little-endian format
            FS_MAGIC,
            total_blocks,
            inode_blocks,
            data_blocks,
            BLOCK_SIZE
        )
        write_sector(f, SUPERBLOCK_SECTOR, superblock_data)

        # 5. Read content for example.txt and write it to the filesystem
        try:
            with open('example.txt', 'rb') as example_file:
                example_content = example_file.read()
        except FileNotFoundError:
            print("Warning: example.txt not found. The image will be created without it.")
            example_content = b''

        if example_content:
            file_size = len(example_content)
            # Place file content at the first available data sector
            file_data_sector = DATA_START_SECTOR + 1

            # Inode Table: Create an inode for example.txt
            pointers = [file_data_sector] + [0] * 13
            # <H: mode, L: size, 14L: pointers, 2x: padding to 64 bytes
            inode_data = struct.pack('<H L 14L 2x', 0x01, file_size, *pointers)
            inode_table_data = inode_data.ljust(BLOCK_SIZE, b'\x00')
            write_sector(f, INODE_TABLE_SECTOR, inode_table_data)

            # Root Directory: Create a directory entry for example.txt
            # <H: inode number, 30s: file name
            dir_entry_data = struct.pack('<H30s', 1, b'example.txt')
            root_dir_data = dir_entry_data.ljust(BLOCK_SIZE, b'\x00')
            write_sector(f, ROOT_DIR_SECTOR, root_dir_data)

            # Write the actual file content to its data sector
            write_sector(f, file_data_sector, example_content)

    print("build/MMT.img created successfully with LPFS filesystem.")

if __name__ == '__main__':
    main()
