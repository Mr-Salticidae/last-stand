$root = "D:\MyGame\LastStand\last-stand\assets\models\quaternius"
$groups = @{
    warehouse = @("Shelf Tall.glb", "Shelf Small.glb", "Crate.glb", "Pallet.glb")
    outpost = @("Barrel.glb", "Bag.glb", "Bags.glb", "Watch Tower.glb", "Tires.glb", "Wood Planks.glb")
    training = @("Stone Wall.glb", "Wooden Wall.glb", "Fence.glb", "Chest.glb")
}

function Get-NodeAabb($g, $nodeIdx, $parentMat) {
    # parentMat is a flat 16-float array (column-major).
    $node = $g.nodes[$nodeIdx]
    # Build local matrix from translation/rotation/scale (or matrix)
    if ($node.matrix -ne $null) {
        $local = $node.matrix
    } else {
        $tx = 0.0; $ty = 0.0; $tz = 0.0
        $sx = 1.0; $sy = 1.0; $sz = 1.0
        $qx = 0.0; $qy = 0.0; $qz = 0.0; $qw = 1.0
        if ($node.translation -ne $null) { $tx=$node.translation[0]; $ty=$node.translation[1]; $tz=$node.translation[2] }
        if ($node.scale -ne $null) { $sx=$node.scale[0]; $sy=$node.scale[1]; $sz=$node.scale[2] }
        if ($node.rotation -ne $null) { $qx=$node.rotation[0]; $qy=$node.rotation[1]; $qz=$node.rotation[2]; $qw=$node.rotation[3] }
        # Quaternion to rotation matrix
        $r00 = 1 - 2*($qy*$qy + $qz*$qz)
        $r01 = 2*($qx*$qy - $qz*$qw)
        $r02 = 2*($qx*$qz + $qy*$qw)
        $r10 = 2*($qx*$qy + $qz*$qw)
        $r11 = 1 - 2*($qx*$qx + $qz*$qz)
        $r12 = 2*($qy*$qz - $qx*$qw)
        $r20 = 2*($qx*$qz - $qy*$qw)
        $r21 = 2*($qy*$qz + $qx*$qw)
        $r22 = 1 - 2*($qx*$qx + $qy*$qy)
        # local = T * R * S, column-major
        $local = @(
            $r00*$sx, $r10*$sx, $r20*$sx, 0,
            $r01*$sy, $r11*$sy, $r21*$sy, 0,
            $r02*$sz, $r12*$sz, $r22*$sz, 0,
            $tx, $ty, $tz, 1
        )
    }
    # world = parent * local
    $w = New-Object 'double[]' 16
    for ($c = 0; $c -lt 4; $c++) {
        for ($r = 0; $r -lt 4; $r++) {
            $sum = 0.0
            for ($k = 0; $k -lt 4; $k++) {
                $sum += $parentMat[$k*4 + $r] * $local[$c*4 + $k]
            }
            $w[$c*4 + $r] = $sum
        }
    }

    $aabb = @{ minX=[double]::PositiveInfinity; minY=[double]::PositiveInfinity; minZ=[double]::PositiveInfinity;
              maxX=[double]::NegativeInfinity; maxY=[double]::NegativeInfinity; maxZ=[double]::NegativeInfinity }

    if ($node.mesh -ne $null) {
        $mesh = $g.meshes[$node.mesh]
        foreach ($prim in $mesh.primitives) {
            $posIdx = $prim.attributes.POSITION
            if ($posIdx -ne $null) {
                $acc = $g.accessors[$posIdx]
                if ($acc.min -ne $null -and $acc.max -ne $null -and $acc.min.Count -eq 3) {
                    # Transform the 8 corners of mesh local AABB by world matrix
                    $corners = @(
                        @($acc.min[0], $acc.min[1], $acc.min[2]),
                        @($acc.max[0], $acc.min[1], $acc.min[2]),
                        @($acc.min[0], $acc.max[1], $acc.min[2]),
                        @($acc.max[0], $acc.max[1], $acc.min[2]),
                        @($acc.min[0], $acc.min[1], $acc.max[2]),
                        @($acc.max[0], $acc.min[1], $acc.max[2]),
                        @($acc.min[0], $acc.max[1], $acc.max[2]),
                        @($acc.max[0], $acc.max[1], $acc.max[2])
                    )
                    foreach ($c in $corners) {
                        $wx = $w[0]*$c[0] + $w[4]*$c[1] + $w[8]*$c[2] + $w[12]
                        $wy = $w[1]*$c[0] + $w[5]*$c[1] + $w[9]*$c[2] + $w[13]
                        $wz = $w[2]*$c[0] + $w[6]*$c[1] + $w[10]*$c[2] + $w[14]
                        if ($wx -lt $aabb.minX) { $aabb.minX = $wx }
                        if ($wy -lt $aabb.minY) { $aabb.minY = $wy }
                        if ($wz -lt $aabb.minZ) { $aabb.minZ = $wz }
                        if ($wx -gt $aabb.maxX) { $aabb.maxX = $wx }
                        if ($wy -gt $aabb.maxY) { $aabb.maxY = $wy }
                        if ($wz -gt $aabb.maxZ) { $aabb.maxZ = $wz }
                    }
                }
            }
        }
    }
    if ($node.children -ne $null) {
        foreach ($cIdx in $node.children) {
            $ca = Get-NodeAabb $g $cIdx $w
            if ($ca.minX -lt $aabb.minX) { $aabb.minX = $ca.minX }
            if ($ca.minY -lt $aabb.minY) { $aabb.minY = $ca.minY }
            if ($ca.minZ -lt $aabb.minZ) { $aabb.minZ = $ca.minZ }
            if ($ca.maxX -gt $aabb.maxX) { $aabb.maxX = $ca.maxX }
            if ($ca.maxY -gt $aabb.maxY) { $aabb.maxY = $ca.maxY }
            if ($ca.maxZ -gt $aabb.maxZ) { $aabb.maxZ = $ca.maxZ }
        }
    }
    return $aabb
}

foreach ($sub in $groups.Keys) {
    Write-Output ""
    Write-Output "--- $sub ---"
    foreach ($nm in $groups[$sub]) {
        $fp = Join-Path -Path (Join-Path $root $sub) -ChildPath $nm
        $bytes = [System.IO.File]::ReadAllBytes($fp)
        $jlen = [BitConverter]::ToUInt32($bytes, 12)
        $jtxt = [System.Text.Encoding]::UTF8.GetString($bytes, 20, $jlen).TrimEnd([char]0, ' ')
        $g = $jtxt | ConvertFrom-Json
        $identity = @(1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,0,0,1.0)
        $sceneIdx = if ($g.scene -ne $null) { $g.scene } else { 0 }
        $aabb = @{ minX=[double]::PositiveInfinity; minY=[double]::PositiveInfinity; minZ=[double]::PositiveInfinity;
                  maxX=[double]::NegativeInfinity; maxY=[double]::NegativeInfinity; maxZ=[double]::NegativeInfinity }
        foreach ($n in $g.scenes[$sceneIdx].nodes) {
            $a = Get-NodeAabb $g $n $identity
            if ($a.minX -lt $aabb.minX) { $aabb.minX = $a.minX }
            if ($a.minY -lt $aabb.minY) { $aabb.minY = $a.minY }
            if ($a.minZ -lt $aabb.minZ) { $aabb.minZ = $a.minZ }
            if ($a.maxX -gt $aabb.maxX) { $aabb.maxX = $a.maxX }
            if ($a.maxY -gt $aabb.maxY) { $aabb.maxY = $a.maxY }
            if ($a.maxZ -gt $aabb.maxZ) { $aabb.maxZ = $a.maxZ }
        }
        $sx = $aabb.maxX - $aabb.minX
        $sy = $aabb.maxY - $aabb.minY
        $sz = $aabb.maxZ - $aabb.minZ
        Write-Output ("{0,-25}  X={1,6:N2}  Y={2,6:N2}  Z={3,6:N2}   y=[{4,5:N2}..{5,5:N2}]" -f $nm, $sx, $sy, $sz, $aabb.minY, $aabb.maxY)
    }
}
