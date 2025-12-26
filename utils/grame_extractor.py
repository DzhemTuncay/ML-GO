import cv2
import os
import argparse
import math

def extract_frames(video_path, output_dir, num_frames):
    os.makedirs(output_dir, exist_ok=True)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if total_frames <= 0:
        raise RuntimeError("Could not determine total frame count")

    # Indices of frames to extract (evenly spaced)
    frame_indices = [
        math.floor(i * total_frames / num_frames)
        for i in range(num_frames)
    ]

    extracted = 0
    current_frame = 0
    target_idx = 0

    while cap.isOpened() and target_idx < num_frames:
        ret, frame = cap.read()
        if not ret:
            break

        if current_frame == frame_indices[target_idx]:
            filename = os.path.join(output_dir, f"frame_{target_idx:04d}.png")
            cv2.imwrite(filename, frame)
            extracted += 1
            target_idx += 1

        current_frame += 1

    cap.release()
    print(f"Extracted {extracted} frames to '{output_dir}'")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract evenly spaced frames from a video")
    parser.add_argument("video", help="Path to input video")
    parser.add_argument("-n", "--num_frames", type=int, default=200, help="Number of frames to extract")
    parser.add_argument("-o", "--output_dir", default="frames", help="Output directory")

    args = parser.parse_args()
    extract_frames(args.video, args.output_dir, args.num_frames)

