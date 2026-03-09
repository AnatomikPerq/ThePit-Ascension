import os

def create_golem():
    content = """[gd_scene load_steps=5 format=3 uid="uid://cgolem01"]

[ext_resource type="Script" uid="uid://3fiq5vux6ie4" path="res://scripts/golem.gd" id="1_script"]
[ext_resource type="Texture2D" uid="uid://cwtsaeeltqr84" path="res://assets/sprites/golem_falling.png" id="2_tex"]

[sub_resource type="RectangleShape2D" id="Shape_Damage"]
size = Vector2(60, 48)

[sub_resource type="RectangleShape2D" id="Shape_Stomp"]
size = Vector2(56, 16)

[node name="Golem" type="Node2D" groups=["enemy"]]
script = ExtResource("1_script")

[node name="Sprite2D" type="Sprite2D" parent="."]
scale = Vector2(2, 2)
texture = ExtResource("2_tex")

[node name="DamageArea" type="Area2D" parent="."]
position = Vector2(0, 8)
collision_layer = 16
collision_mask = 2

[node name="CollisionShape2D" type="CollisionShape2D" parent="DamageArea"]
shape = SubResource("Shape_Damage")

[node name="StompArea" type="Area2D" parent="."]
position = Vector2(0, -24)
collision_layer = 16
collision_mask = 10

[node name="CollisionShape2D" type="CollisionShape2D" parent="StompArea"]
shape = SubResource("Shape_Stomp")
"""
    with open("scenes/Golem.tscn", "w", encoding="utf-8") as f:
        f.write(content)

def create_slime():
    content = """[gd_scene load_steps=5 format=3 uid="uid://cslime01"]

[ext_resource type="Script" uid="uid://cyafnn114fsq6" path="res://scripts/slime.gd" id="1_script"]
[ext_resource type="Texture2D" uid="uid://dbxdigit1inet" path="res://assets/sprites/slime_falling.png" id="2_tex"]

[sub_resource type="RectangleShape2D" id="Shape_Damage"]
size = Vector2(60, 32)

[sub_resource type="RectangleShape2D" id="Shape_Stomp"]
size = Vector2(56, 16)

[node name="Slime" type="Node2D" groups=["enemy"]]
script = ExtResource("1_script")

[node name="Sprite2D" type="Sprite2D" parent="."]
scale = Vector2(2, 2)
texture = ExtResource("2_tex")

[node name="DamageArea" type="Area2D" parent="."]
position = Vector2(0, 8)
collision_layer = 16
collision_mask = 2

[node name="CollisionShape2D" type="CollisionShape2D" parent="DamageArea"]
shape = SubResource("Shape_Damage")

[node name="StompArea" type="Area2D" parent="."]
position = Vector2(0, -16)
collision_layer = 16
collision_mask = 10

[node name="CollisionShape2D" type="CollisionShape2D" parent="StompArea"]
shape = SubResource("Shape_Stomp")
"""
    with open("scenes/Slime.tscn", "w", encoding="utf-8") as f:
        f.write(content)

def create_pursuer():
    content = """[gd_scene load_steps=6 format=3 uid="uid://cpursuer01"]

[ext_resource type="Script" uid="uid://j5v5rxnfclk7" path="res://scripts/pursuer.gd" id="1_script"]
[ext_resource type="Texture2D" uid="uid://bbtu1vlwcv5l0" path="res://assets/sprites/pursuer_1.png" id="2_tex"]

[sub_resource type="RectangleShape2D" id="Shape_Body"]
size = Vector2(56, 80)

[sub_resource type="RectangleShape2D" id="Shape_Damage"]
size = Vector2(52, 64)

[sub_resource type="RectangleShape2D" id="Shape_Stomp"]
size = Vector2(48, 16)

[node name="Pursuer" type="CharacterBody2D" groups=["enemy"]]
collision_layer = 16
script = ExtResource("1_script")

[node name="Sprite2D" type="Sprite2D" parent="."]
scale = Vector2(2, 2)
texture = ExtResource("2_tex")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("Shape_Body")

[node name="DamageArea" type="Area2D" parent="."]
position = Vector2(0, 8)
collision_layer = 16
collision_mask = 2

[node name="CollisionShape2D" type="CollisionShape2D" parent="DamageArea"]
shape = SubResource("Shape_Damage")

[node name="StompArea" type="Area2D" parent="."]
position = Vector2(0, -32)
collision_layer = 16
collision_mask = 10

[node name="CollisionShape2D" type="CollisionShape2D" parent="StompArea"]
shape = SubResource("Shape_Stomp")

[node name="EdgeDetector" type="RayCast2D" parent="."]
position = Vector2(30, 40)
target_position = Vector2(0, 20)

[node name="WallDetector" type="RayCast2D" parent="."]
position = Vector2(30, 0)
target_position = Vector2(20, 0)
"""
    with open("scenes/Pursuer.tscn", "w", encoding="utf-8") as f:
        f.write(content)

if __name__ == "__main__":
    create_golem()
    create_slime()
    create_pursuer()
    print("Enemy scenes rebuilt successfully!")
