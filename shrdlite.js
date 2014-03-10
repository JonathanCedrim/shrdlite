
// URL to the Ajax CGI script:
var AjaxScript = "cgi-bin/ajaxwrapper.py";

// List of the JSON files that contain example worlds:
var ExampleNames = ["ex1"];

// What the system says when it has nothing to do:
var SystemPromptText = "What can I do for you today?";

// Constants that you can play around with:
var DialogueHistory = 100;// max nr. utterances
var FloorThickness = 10; // pixels
var BoxThickness = 0.1; // relative to stack width
var BoxSpacing = 4;    // pixels
var ArmSize = 20;     // pixels
var ArmSpeed = 1000; // pixels per second
var AnimationPause = 0.1; // seconds
var PromptPause = 0.5;   // seconds
var AjaxTimeout = 5;    // seconds


//==============================================================================
//
// Don't change anything below this line, if you don't know what you are doing.
//
//==============================================================================

var CanvasWidth;
var CanvasHeight;

var Pick = 'pick';
var Drop = 'drop';

var SvgNS = 'http://www.w3.org/2000/svg';

var BlockData = {
    "rectangle": {"tall":   {"width":0.50, "height":1.00},
                  "wide":   {"width":1.00, "height":0.50}
                 },
    "ball":      {"small":  {"width":0.50, "height":0.50},
                  "medium": {"width":0.75, "height":0.75},
                  "large":  {"width":1.00, "height":1.00}
                 },
    "square":    {"small":  {"width":0.50, "height":0.50},
                  "medium": {"width":0.75, "height":0.75},
                  "large":  {"width":1.00, "height":1.00}
                 },
    "pyramid":   {"small":  {"width":0.50, "height":0.50},
                  "medium": {"width":0.75, "height":0.75},
                  "large":  {"width":1.00, "height":1.00}
                 },
    "box":       {"small":  {"width":0.50, "height":0.50},
                  "medium": {"width":0.75, "height":0.75},
                  "large":  {"width":1.00, "height":1.00}
                 }
};

var ExampleWorlds;
var currentExample;
var currentWorld;
var currentPlan;
var currentArmPosition;

function stackWidth() {
    return CanvasWidth / currentWorld.world.length;
}

$(function() {
    $('#inputform').submit(function(){
        userInput();
        return false;
    });
    $('#inputexamples').change(function(){
        userInput();
        return false;
    });
    $('#showdebug').click(function(){
        $('#debug').toggle($('#showdebug').prop('checked'));
    });
    CanvasWidth = $("#svgdiv").width();
    CanvasHeight = $("#svgdiv").height() - FloorThickness;
    loadExampleWorlds();
    resetCurrentExample(ExampleNames[0]);
});

function loadExampleWorlds() {
    ExampleWorlds = {};
    $.each(ExampleNames, function(i, name) {
        $('<input type="submit">').val(name)
            .click(changeCurrentExample)
            .appendTo($("#exampleworlds"));
        $.ajax({
            dataType: "json",
            url: name + ".json",
            async: false
        }).fail(function(jqxhr, status, error) {
            alertError("Couldn't load example '" + name + "'.json: " + status, error);
        }).done(function(world) {
            ExampleWorlds[name] = world;
        });
    });
}

function changeCurrentExample() {
    var name = $(this).val();
    if (confirm('Are you certain that you want to reset to "' + name + '"?')) {
        resetCurrentExample(name);
    }
}

function resetCurrentExample(name) {
    currentExample = name;
    currentWorld = ExampleWorlds[currentExample];
    currentArmPosition = 0;
    $('#inputexamples').empty();
    $('#inputexamples').append($('<option value="">').text("(Select an example utterance)"));
    $.each(currentWorld.examples, function(i,value) {
        if (value instanceof Array) value = value.join(" ");
        $('#inputexamples').append($('<option>').text(value));
    });
    $("#dialogue > p").remove();
    resetSVG();
}

function resetSVG() {
    disableInput();
    $("#response").empty();
    addUtterance("system", "Please wait while I populate the world.");
    $('#svgdiv').empty();

    var viewBox = [0, 0, CanvasWidth, CanvasHeight + FloorThickness];
    var svg = $(SVG('svg')).attr({
        viewBox: viewBox.join(' '), 
        width: viewBox[2], 
        height: viewBox[3],
    }).appendTo($('#svgdiv'));

    $(SVG('rect')).attr({
        x: 0,
        y: CanvasHeight,
        width: CanvasWidth,
        height: CanvasHeight + FloorThickness,
        fill: 'black',
    }).appendTo(svg);

    $(SVG('line')).attr({
        id:'arm',
        x1: stackWidth() / 2,
        y1: ArmSize - CanvasHeight, 
        x2: stackWidth() / 2, 
        y2: ArmSize, 
        stroke: 'black', 
        'stroke-width': ArmSize,
    }).appendTo(svg);

    var timeout = 0;
    for (var stacknr=0; stacknr < currentWorld.world.length; stacknr++) {
        for (var blocknr=0; blocknr < currentWorld.world[stacknr].length; blocknr++) {
            var blockid = currentWorld.world[stacknr][blocknr];
            makeBlock(svg, blockid, stacknr, timeout);
            timeout += AnimationPause;
        }
    }
    debugWorld();
    systemPrompt(timeout + PromptPause);
}

function SVG(tag) {
    return document.createElementNS(SvgNS, tag);
}

function animateMotion(object, path, timeout, duration) {
    if (path instanceof Array) {
        path = path.join(" ");
    }
    var animation = SVG('animateMotion');
    $(animation).attr({
        begin: 'indefinite',
        fill: 'freeze',
        path: path,
        dur: duration,
    }).appendTo(object);
    animation.beginElementAt(timeout);
    return animation;
}

function moveBlock(action, stackNr) {
    if (action == Pick && currentWorld.holding) {
        alertError("ERROR", "I cannot pick a block from stack " + stackNr + ", I am already holding something!")
        return 0;
    } else if (action == Drop && !currentWorld.holding) {
        alertError("ERROR", "I cannot drop a block onto stack " + stackNr + ", I am not holding anything!")
        return 0;
    }
    var stack = currentWorld.world[stackNr];
    var arm = $('#arm');
    var xStack = stackNr * stackWidth();
    var xArm = currentArmPosition * stackWidth();

    if (action == Pick) {
        if (!stack.length) {
            alertError("ERROR", "I cannot pick a block from stack " + stackNr + ", it is empty!")
            return 0;
        }
        currentWorld.holding = stack.pop();
    }

    var altitude = getAltitude(stack);
    var blockHeight = getBlockDimensions(currentWorld.holding).height;
    var yArm = CanvasHeight - altitude - ArmSize - blockHeight;
    var yStack = -altitude;

    var path1 = ["M", xArm, 0, "H", xStack, "V", yArm];
    var path2 = ["M", xStack, yArm, "V", 0];
    var duration1 = (Math.abs(xStack - xArm) + Math.abs(yArm)) / ArmSpeed;
    var duration2 = (Math.abs(yArm)) / ArmSpeed;
    var anim1 = animateMotion(arm, path1, 0, duration1);
    var anim2 = animateMotion(arm, path2, duration1 + AnimationPause, duration2);

    if (action == Pick) {
        var path2b = ["M", xStack, yStack, "V", yStack-yArm];
        animateMotion($("#"+currentWorld.holding), path2b, duration1 + AnimationPause, duration2)
    } else if (action == Drop) {
        var path1b = ["M", xArm, yStack-yArm, "H", xStack, "V", yStack];
        animateMotion($("#"+currentWorld.holding), path1b, 0, duration1)
    }

    if (action == Drop) {
        stack.push(currentWorld.holding);
        currentWorld.holding = null;
    }
    currentArmPosition = stackNr;
    debugWorld();
    return duration1 + duration2 + 2 * AnimationPause;
}

function getBlockDimensions(blockid) {
    var attrs = currentWorld.blocks[blockid];
    var size = BlockData[attrs.form][attrs.size];
    var width = size.width * (stackWidth() - BoxSpacing);
    var height = size.height * (stackWidth() - BoxSpacing);
    var boxThickness = width * BoxThickness;
    boxThickness = Math.max(5, Math.min(boxThickness, stackWidth() / 5));
    var heightadd = boxThickness;
    if (attrs.form != 'box') {
        width -= 2 * (boxThickness + BoxSpacing);
        height -= 2 * (boxThickness + BoxSpacing);
        heightadd = height;
    }
    return {
        width: width,
        height: height,
        heightadd: heightadd,
        thickness: boxThickness,
    };
}

function getAltitude(stack, blockid) {
    var altitude = 0;
    for (var i=0; i<stack.length; i++) {
        if (blockid == stack[i])
            break;
        altitude += getBlockDimensions(stack[i]).heightadd + BoxSpacing;
    }
    return altitude;
}

function makeBlock(svg, blockid, stacknr, timeout) {
    var attrs = currentWorld.blocks[blockid];
    var altitude = getAltitude(currentWorld.world[stacknr], blockid);
    var dim = getBlockDimensions(blockid);

    var ybottom = CanvasHeight;
    var ytop = ybottom - dim.height;
    var ycenter = (ybottom + ytop) / 2;
    var yradius = (ybottom - ytop) / 2;
    var xleft = (stackWidth() - dim.width) / 2
    var xright = xleft + dim.width;
    var xcenter = (xright + xleft) / 2;
    var xradius = (xright - xleft) / 2;

    var block;
    switch (attrs.form) {
    case 'square':
    case 'rectangle':
        block = $(SVG('rect')).attr({
            x: xleft, 
            y: ytop, 
            width: dim.width, 
            height: dim.height
        });
        break;
    case 'ball':
        block = $(SVG('ellipse')).attr({
            cx: xcenter, 
            cy: ycenter, 
            rx: xradius, 
            ry: yradius
        });
        break;
    case 'pyramid':
        var points = [xleft, ybottom, xcenter, ytop, xright, ybottom];
        block = $(SVG('polygon')).attr({
            points: points.join(" ")
        });
        break;
    case 'box':
        var points = [xleft, ytop, xleft, ybottom, xright, ybottom, xright, ytop, 
                      xright-dim.thickness, ytop, xright-dim.thickness, ybottom-dim.thickness,
                      xleft+dim.thickness, ybottom-dim.thickness, xleft+dim.thickness, ytop];
        block = $(SVG('polygon')).attr({
            points: points.join(" ")
        });
        break;
    }
    block.attr({
        id: blockid,
        stroke: 'black', 
        'stroke-width': 2, 
        fill: attrs.color, 
    });
    block.appendTo(svg);

    var path = ["M", stacknr * stackWidth(), -(CanvasHeight + FloorThickness)];
    animateMotion(block, path, 0, 0);
    path.push("V", -altitude);
    animateMotion(block, path, timeout, 0.5);
}

function disableInput(timeout) {
    if (timeout) {
        setTimeout(disableInput, 1000*timeout);
    } else {
        $("#inputexamples").blur();
        $("#inputexamples").prop('disabled', true); 
        $("#userinput").blur();
        $("#userinput").prop('disabled', true); 
    }
}

function systemPrompt(timeout) {
    if (timeout) {
        setTimeout(systemPrompt, 1000*timeout);
    } else {
        addUtterance("system", SystemPromptText);
        enableInput();
    }
}

function enableInput() {
    $("#inputexamples").prop('disabled', false).val(''); 
    $("#inputexamples option:first").attr('selected','selected');
    $("#userinput").prop('disabled', false); 
    $("#userinput").focus().select();
}

function performPlan() {
    if (currentPlan && currentPlan.length) {
        var item = currentPlan.shift();
        var timeout = 0;
        var action = getAction(item);
        if (action) {
            timeout = moveBlock(action[0], action[1]);
        } else if (item && item[0] != "#") {
            addUtterance("system", item);
        }
        setTimeout(performPlan, 1000 * timeout);
    } else {
        systemPrompt(PromptPause);
    }
}

function getAction(item) {
    if (typeof(item) == "string") item = item.trim().split(/\s+/);
    if (item.length == 2 &&
        (item[0] == Pick || item[0] == Drop) &&
        /^\d+$/.test(item[1]))
    {
        item[1] = parseInt(item[1]);
        return item;
    }
    return null;
}

function splitAction(action) {
}

function userInput() {
    var userinput = $("#inputexamples").val();
    if (userinput) {
        $("#userinput").val(userinput.trim());
        enableInput();
        return;
    }
    userinput = $("#userinput").val().trim();
    if (!userinput) {
        enableInput();
        return;
    }
    disableInput();

    addUtterance("user", userinput);

    var ajaxdata = {'world': currentWorld.world,
                    'blocks': currentWorld.blocks,
                    'holding': currentWorld.holding,
                    'utterance': userinput.split(/\s+/)
                   };

    $.ajax({
        url: AjaxScript,
        dataType: "text",
        cache: false,
        timeout: 1000 * AjaxTimeout,
        data: {'data': JSON.stringify(ajaxdata)}
    }).fail(function(jqxhr, status, error) {
        alertError("Internal error: " + status, error);
        systemPrompt();
    }).done(function(result) {
        try {
            result = JSON.parse(result);
        } catch(err) {
            alertError("JSON error:" + err, result);
        }
        debugResult(result);
        addUtterance("system", result.output);
        currentPlan = result.plan;
        performPlan();
    });
}

function addUtterance(participant, utterance) {
    var dialogue = $("#dialogue");
    if (dialogue.children().length > DialogueHistory) {
        dialogue.children().first().remove();
    }
    $('<p>').attr("class", participant)
        .text(utterance)
        .insertBefore($("#inputform"));
    dialogue.scrollTop(dialogue.prop("scrollHeight"));
}

function debugWorld() {
    $("#debugworld").html("<table><tr><td>&nbsp;" + currentWorld.world.join("&nbsp;<td>&nbsp;") + "&nbsp;</tr></table>");
    $("#debugholding").html(currentWorld.holding || "&mdash;");
}

function debugResult(result) {
    $("#debugoutput").text(result.output);
    $("#debugtrees").html(result.trees ? result.trees.join("<br>") : "&mdash;");
    $("#debuggoals").html(result.goals ? result.goals.join("<br>") : "&mdash;");
    $("#debugplan").html(result.plan ? result.plan.join("<br>") : "&mdash;");
    $("#debugjson").text(JSON.stringify(result, null, " "));
}

function alertError(title, description) {
    if (typeof(description) !== "string") description = JSON.stringify(description);
    addUtterance("error", "[" + title + "] " + description);
    console.log("*** " + title + " ***");
    console.log(description);
}