# Renamed Labels for Invaders

This file maps the original, cryptic `in...` labels from the book's source code to new, descriptive names for use in the refactored project.

| Original Label | New Label Name          | Description                                                    |
| :------------- | :---------------------- | :------------------------------------------------------------- |
| `in1`          | `reset_invader_rows`    | **User-provided.** Outer loop to set up all 5 rows of invaders.      |
| `in5`          | `set_invader_positions` | **User-provided.** Inner loop to set up the 11 invaders in a single row. |
| `in0`          | `draw_sprite_pixel_loop`| Inner loop within `draw_sprite`; draws one 2x2 "big pixel".    |
| `in2`          | `animate_living_invader`| Entry point for a living invader; animates it and syncs game speed. |
| `in3`          | `draw_sprite_row_loop`  | Outer loop within `draw_sprite`; iterates through each row of the sprite bitmap. |
| `in4`          | `check_invader_fire`    | Checks a random condition to see if the current invader should fire a bullet. |
| `in6`          | `process_next_invader`  | The main part of the invader update loop; loads the invader's data to process it. |
| `in7`          | `handle_bullet_barrier_collision` | Bullet has hit a barrier; deletes the bullet and erases the barrier pixel. |
| `in8`          | `update_invader_position`| Saves the invader's new calculated position back to the sprites table. |
| `in9`          | `move_invader_horizontal`| Adjusts the invader's `ax` position value left or right based on swarm direction. |
| `in10`         | `exit_game`             | Restores text mode (if a COM file) and exits to the operating system. |
| `in12`         | `skip_clock_wait`       | Skips the `je` loop that waits for the BIOS clock to tick over. |
| `in14`         | `frame_start`           | The beginning of the main game loop for a single frame.        |
| `in17`         | `handle_move_left`      | Checks for the 'Ctrl' key and moves the player ship left.      |
| `in18`         | `handle_move_right`     | Checks for the 'Alt' key and moves the player ship right.      |
| `in19`         | `update_ship_position`  | Saves the player ship's new position to the sprites table.     |
| `in20`         | `check_invader_bounds`  | Checks if the invader swarm has touched the left or right screen edge. |
| `in22`         | `wait_for_clock_tick`   | The `je` loop that busy-waits for the BIOS clock to change.     |
| `in23`         | `next_invader_bullet`   | Jumps to the next iteration of the invader bullet update loop. |
| `in24`         | `update_invader_bullets_loop` | The main loop that processes each of the invader bullets. |
| `in27`         | `skip_drawing_destroyed_invader` | Jumps to the next invader if the current one is already marked as destroyed. |
| `in29`         | `draw_invader_sprite`   | Calls `draw_sprite` for the current invader.                  |
| `in30`         | `draw_bullet`           | Draws a bullet (player or invader) at its new position.      |
| `in31`         | `delete_bullet`         | Deletes a bullet from the active shots table (by zeroing its position). |
| `in35`         | `skip_player_fire`      | Skips the player firing logic if Shift isn't pressed or a bullet is already active. |
| `in41`         | `skip_player_hit`       | Jumps here if an invader bullet did *not* hit the player ship. |
| `in42`         | `update_spaceship_sprite`| Updates the spaceship's sprite frame (e.g., for explosions).   |
| `in43`         | `skip_ship_position_update` | Skips saving the ship's position (e.g., if it's at a screen edge). |
| `in44`         | `found_empty_bullet_slot`| Jumps here when a free slot for an invader bullet is found.    |
| `in45`         | `find_empty_bullet_slot_loop` | The loop that searches for a free slot in the invader bullet table. |
| `in46`         | `update_invaders_loop`  | The main loop that iterates through all 55 invaders to update them. |
| `in48`         | `draw_barriers_loop`    | The loop that draws the 5 protective barriers on the screen during setup. |

