﻿function StandardDeviation {
    param (
        [double[]]$numbers
    )
    $avg = $numbers | Measure-Object -Average | select Count, Average;
    $popdev = 0;
    foreach($number in $numbers) {
        $popdev += [math]::pow(($number - $avg.Average), 2);
    }
    $sd = [math]::sqrt($popdev / ($avg.Count - 1));
    return $sd;
}


$hsk1Words = @("一", "一点儿", "七", "三", "上", "上午", "下", "下午", "下雨", "不", "不客气", "东西", "个", "中午", "中国", "九", "书", "买", "了", "二", "五", "些", "人", "什么", "今天", "他", "会", "住", "你", "做", "儿子", "先生", "八", "六", "再见", "写", "冷", "几", "出租车", "分钟", "前面", "北京", "医生", "医院", "十", "去", "叫", "号", "吃", "同学", "名字", "后面", "吗", "听", "呢", "和", "哪", "哪儿", "商店", "喂", "喜欢", "喝", "四", "回", "在", "坐", "块", "多", "多少", "大", "天气", "太", "女儿", "她", "好", "妈妈", "字", "学习", "学校", "学生", "家", "对不起", "小", "小姐", "少", "岁", "工作", "年", "开", "很", "怎么", "怎么样", "想", "我", "我们", "打电话", "时候", "明天", "星期", "昨天", "是", "月", "有", "朋友", "本", "来", "杯子", "桌子", "椅子", "水", "水果", "汉语", "没关系", "没有", "漂亮", "点", "热", "爱", "爸爸", "狗", "猫", "现在", "电影", "电脑", "电视", "的", "看", "看见", "睡觉", "米饭", "老师", "能", "苹果", "茶", "菜", "衣服", "认识", "说", "请", "读", "谁", "谢谢", "这", "那", "都", "里");
$hsk1Characters = @{};
foreach ($word in $hsk1Words) {
    foreach($character in $word.toCharArray()) {
        $hsk1Characters[$character] = $true;
    }
}

$wordPositions=@{};
$i=1;
$text=Get-Content -Raw $args[0] -Encoding UTF8
Foreach ($character in $text.ToCharArray()) {
    if (!$wordPositions[$character]) {
        $wordPositions[$character] = [System.Collections.ArrayList]@();
    }
    $wordPositions[$character].Add($i) | Out-Null;
    $i += 1;
}

$wordCounts = @{};
foreach ($character in $wordPositions.GetEnumerator()) {
    $wordCounts[$character.Name] = $character.Value;
}

$standardDeviations = @{};
foreach ($character in $wordPositions.GetEnumerator()) {
    $decimals = $character.Value | % { $_ / $i };
    if ($decimals.Length.Equals(1)) {
        $sd = 0;
    }
    else {
        $sd = StandardDeviation $decimals;
    }
    $standardDeviations[$character.Name] = @{Deviation = $sd; Positions = $decimals | % { ([math]::Round($_, 2) * 100).toString() + "%" }}
}

$standardDeviations.GetEnumerator() | Sort-Object -Property {$_.Value['Deviation']} -Descending | Select -Property {
    $d = [math]::Round($_.Value["Deviation"], 3);
    $p = $_.Value["Positions"];
    $c = $_.Key;
    return "$c $d ($p)"
}