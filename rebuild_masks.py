import os

def update_masks(files):
    for filepath in files:
        if not os.path.exists(filepath):
            continue
            
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            
        out = []
        in_stomp_or_damage = False
        
        for line in lines:
            if line.startswith('[node name="DamageArea"') or line.startswith('[node name="StompArea"'):
                in_stomp_or_damage = True
            elif line.startswith('[node '):
                in_stomp_or_damage = False
                
            if in_stomp_or_damage and line.startswith('collision_mask = '):
                out.append('collision_mask = 10\n')
                continue
                
            out.append(line)
            
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(out)

if __name__ == '__main__':
    files = [
        "scenes/Golem.tscn",
        "scenes/Slime.tscn",
        "scenes/Pursuer.tscn"
    ]
    update_masks(files)
    print("Enemy Area2D masks updated to 10 (Player + Strike).")
